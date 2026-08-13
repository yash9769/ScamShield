import os
import shutil
import glob

def cleanup():
    base_dir = '/Users/sam/Downloads/scamshield'
    os.chdir(base_dir)
    print("Starting cleanup for zipping...")
    
    # Delete Android build artifacts
    android_gradle = os.path.join(base_dir, 'android', '.gradle')
    if os.path.exists(android_gradle):
        print(f"Deleting {android_gradle}...")
        shutil.rmtree(android_gradle)
    
    android_kotlin = os.path.join(base_dir, 'android', '.kotlin')
    if os.path.exists(android_kotlin):
        print(f"Deleting {android_kotlin}...")
        shutil.rmtree(android_kotlin)
    
    iml_file = os.path.join(base_dir, 'android', 'scamshield_android.iml')
    if os.path.exists(iml_file):
        print(f"Deleting {iml_file}...")
        os.remove(iml_file)
    
    # Delete all __pycache__ directories
    print("Deleting all __pycache__ directories...")
    for pycache in glob.glob('**/__pycache__', recursive=True):
        try:
            shutil.rmtree(pycache)
        except:
            pass
    
    # Delete pytest cache
    pytest_cache = os.path.join(base_dir, 'backend', '.pytest_cache')
    if os.path.exists(pytest_cache):
        print(f"Deleting {pytest_cache}...")
        shutil.rmtree(pytest_cache)
    
    # Delete database file
    db_file = os.path.join(base_dir, 'backend', 'scamshield_audit.db')
    if os.path.exists(db_file):
        print(f"Deleting {db_file}...")
        os.remove(db_file)
    
    # Delete all .log files
    print("Deleting all *.log files...")
    for log_file in glob.glob('**/*.log', recursive=True):
        try:
            os.remove(log_file)
        except:
            pass
    
    print("Cleanup complete!")

if __name__ == "__main__":
    cleanup()