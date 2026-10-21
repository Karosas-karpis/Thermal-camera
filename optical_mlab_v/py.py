import os
import argparse
from pathlib import Path

# The specific file extensions we want to feed to the LLM
VALID_EXTENSIONS = {".v", ".sv", ".vh", ".svh", ".xdc"}

def is_ignored_vivado_dir(dir_name):
    """Dynamically catch Vivado's auto-generated project folders."""
    # Catch hidden folders
    if dir_name.startswith('.'): 
        return True
        
    # Catch dynamic <project_name>.* folders that Vivado generates
    dynamic_ignores = ('.gen', '.cache', '.runs', '.ip_user_files', '.hw', '.sim')
    if dir_name.endswith(dynamic_ignores): 
        return True
        
    # Exact folder names to skip (IP cores, Block Designs, Simulation run artifacts)
    exact_ignores = {"ip", "bd", "xsim.dir", "synth_1", "impl_1", "managed_ip_project", "ip_shared"}
    
    return dir_name in exact_ignores

def pack_vivado_project(target_dir, output_file):
    target_path = Path(target_dir)
    files_processed = 0
    
    with open(output_file, 'w', encoding='utf-8') as outfile:
        outfile.write("==== VIVADO SYSTEMVERILOG PROJECT ====\n\n")
        
        for root, dirs, files in os.walk(target_path):
            # Prune the directory tree in-place to skip Vivado junk
            dirs[:] = [d for d in dirs if not is_ignored_vivado_dir(d)]
            
            for file in files:
                file_path = Path(root) / file
                
                if file_path.suffix in VALID_EXTENSIONS:
                    try:
                        with open(file_path, 'r', encoding='utf-8') as infile:
                            content = infile.read()
                            
                        rel_path = file_path.relative_to(target_path)
                        
                        outfile.write(f"{'='*60}\n")
                        outfile.write(f"==== FILE: {rel_path} ====\n")
                        outfile.write(f"{'='*60}\n")
                        outfile.write(content)
                        outfile.write("\n\n")
                        
                        files_processed += 1
                        print(f"Added: {rel_path}")
                        
                    except UnicodeDecodeError:
                        print(f"Skipped (Binary): {file_path}")

    print(f"\nSuccessfully packed {files_processed} user files into {output_file}")

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Pack Vivado user RTL for LLMs.")
    parser.add_argument("-d", "--dir", default=".", help="Project root (default: current dir)")
    parser.add_argument("-o", "--out", default="vivado_llm_context.txt", help="Output text file")
    
    args = parser.parse_args()
    pack_vivado_project(args.dir, args.out)