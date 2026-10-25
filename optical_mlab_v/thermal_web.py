#!/usr/bin/env python3
"""Headless MJPEG server for the Waveshare/SenXor MI48 thermal camera."""

import logging
import os
import signal
import sys
import threading
import time

import cv2 as cv
import numpy as np
from flask import Flask, Response
from gpiozero import DigitalInputDevice, DigitalOutputDevice
from smbus import SMBus
from spidev import SpiDev

from senxor.interfaces import I2C_Interface, SPI_Interface
from senxor.mi48 import DATA_READY, MI48
from senxor.utils import data_to_frame


I2C_CHANNEL = 1
I2C_ADDRESS = 0x40

SPI_BUS = 0
SPI_DEVICE = 0  # /dev/spidev0.0
SPI_SPEED_HZ = 1_000_000
SPI_TRANSFER_BYTES = 160
SPI_CS_DELAY_SECONDS = 0.0001

TARGET_FPS = 6
OUTPUT_SIZE = (320, 248)
JPEG_QUALITY = 70

logging.basicConfig(
    level=os.environ.get("LOGLEVEL", "INFO"),
    format="%(asctime)s %(levelname)s %(message)s",
)
logger = logging.getLogger(__name__)
app = Flask(__name__)

frame_condition = threading.Condition()
latest_jpeg = None
frame_sequence = 0
stop_event = threading.Event()


class MI48Reset:
    def __init__(self, pin):
        self.pin = pin

    def __call__(self):
        logger.info("Resetting MI48")
        self.pin.on()
        time.sleep(0.000035)
        self.pin.off()
        time.sleep(0.050)


i2c = I2C_Interface(SMBus(I2C_CHANNEL), I2C_ADDRESS)

spi_device = SpiDev(SPI_BUS, SPI_DEVICE)
spi_device.mode = 0
spi_device.max_speed_hz = SPI_SPEED_HZ
spi_device.bits_per_word = 8
spi_device.lsbfirst = False
spi_device.no_cs = True
spi = SPI_Interface(spi_device, xfer_size=SPI_TRANSFER_BYTES)

spi_cs_n = DigitalOutputDevice("BCM7", active_high=False, initial_value=False)
data_ready = DigitalInputDevice("BCM24", pull_up=False)
reset_n = DigitalOutputDevice("BCM23", active_high=False, initial_value=True)

mi48 = MI48(
    [i2c, spi],
    data_ready=data_ready,
    reset_handler=MI48Reset(reset_n),
)


def capture_frames():
    global latest_jpeg, frame_sequence

    logger.info("Camera info: %s", mi48.get_camera_info())
    mi48.set_fps(TARGET_FPS)
    if int(mi48.fw_version[0]) >= 2:
        mi48.enable_filter(f1=True, f2=True, f3=False)
        mi48.set_offset_corr(0.0)
    mi48.start(stream=True, with_header=True)

    try:
        while not stop_event.is_set():
            if hasattr(mi48, "data_ready"):
                if not mi48.data_ready.wait_for_active(timeout=1):
                    continue
            else:
                while not stop_event.is_set():
                    if mi48.get_status() & DATA_READY:
                        break
                    time.sleep(0.01)

            spi_cs_n.on()
            try:
                time.sleep(SPI_CS_DELAY_SECONDS)
                data, _header = mi48.read()
                time.sleep(SPI_CS_DELAY_SECONDS)
            finally:
                spi_cs_n.off()

            if data is None:
                logger.warning("Camera returned no frame")
                continue

            data = np.asarray(data)
            if (
                not np.all(np.isfinite(data))
                or data.min() < -80
                or data.max() > 500
            ):
                logger.warning(
                    "Dropping invalid frame: min=%.2f max=%.2f",
                    float(np.nanmin(data)),
                    float(np.nanmax(data)),
                )
                continue

            image = data_to_frame(data, mi48.fpa_shape)
            image_8bit = cv.normalize(
                image.astype(np.float32),
                None,
                0,
                255,
                cv.NORM_MINMAX,
                dtype=cv.CV_8U,
            )
            image_color = cv.applyColorMap(image_8bit, cv.COLORMAP_INFERNO)
            image_color = cv.resize(
                image_color,
                OUTPUT_SIZE,
                interpolation=cv.INTER_NEAREST,
            )

            encoded, jpeg = cv.imencode(
                ".jpg",
                image_color,
                [cv.IMWRITE_JPEG_QUALITY, JPEG_QUALITY],
            )
            if not encoded:
                logger.warning("JPEG encoding failed")
                continue

            with frame_condition:
                latest_jpeg = jpeg.tobytes()
                frame_sequence += 1
                frame_condition.notify_all()
    except Exception:
        logger.exception("Capture thread stopped unexpectedly")
        stop_event.set()
        with frame_condition:
            frame_condition.notify_all()
    finally:
        try:
            mi48.stop(stop_timeout=1.0)
        except Exception:
            logger.exception("Could not stop MI48 cleanly")


def mjpeg_stream():
    seen_sequence = -1
    while not stop_event.is_set():
        with frame_condition:
            frame_condition.wait_for(
                lambda: frame_sequence != seen_sequence or stop_event.is_set(),
                timeout=2,
            )
            if stop_event.is_set():
                return
            frame = latest_jpeg
            seen_sequence = frame_sequence

        if frame is not None:
            yield (
                b"--frame\r\n"
                b"Content-Type: image/jpeg\r\n"
                b"Cache-Control: no-cache\r\n\r\n"
                + frame
                + b"\r\n"
            )


@app.route("/")
def index():
    return """
<!doctype html>
<html>
  <head>
    <meta charset="utf-8">
    <title>MI48 Thermal Camera</title>
  </head>
  <body style="background:#111;color:#eee;text-align:center;font-family:sans-serif">
    <h2>MI48 Thermal Camera</h2>
    <img src="/video_feed" width="320" height="248"
         style="image-rendering:pixelated;border:2px solid #444">
  </body>
</html>
"""


@app.route("/video_feed")
def video_feed():
    return Response(
        mjpeg_stream(),
        mimetype="multipart/x-mixed-replace; boundary=frame",
    )


def shutdown(_signal=None, _frame=None):
    stop_event.set()
    with frame_condition:
        frame_condition.notify_all()
    if _signal is not None:
        raise SystemExit(0)


if __name__ == "__main__":
    signal.signal(signal.SIGINT, shutdown)
    signal.signal(signal.SIGTERM, shutdown)

    capture_thread = threading.Thread(
        target=capture_frames,
        name="mi48-capture",
        daemon=True,
    )
    capture_thread.start()

    try:
        app.run(
            host="0.0.0.0",
            port=5000,
            threaded=True,
            use_reloader=False,
        )
    finally:
        shutdown()
        capture_thread.join(timeout=2)
        spi_cs_n.close()
        data_ready.close()
        reset_n.close()
        spi.close()
        i2c.close()
