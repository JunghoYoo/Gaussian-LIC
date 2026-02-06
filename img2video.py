import cv2
import glob
import os
import re
import subprocess
import sys

def extract_leading_number(filename):
    base = os.path.basename(filename)
    match = re.search(r"train_(\d+)", base)
    return int(match.group(1)) if match else float('inf')

if __name__ == "__main__":
    # --- Configuration ---
    image_path = './result/gt'
    fps = 5
    # Choose your GPU Codec: 'h264_nvenc' (Best compatibility) or 'av1_nvenc' (Best tech for 5090)
    gpu_codec = 'h264_nvenc' 
    output_filename = "render_" + gpu_codec + ".mp4"
    # ---------------------

    image_dir = os.path.abspath(image_path)
    print(f"Processing directory: {image_dir}")

    image_files = sorted(
        glob.glob(os.path.join(image_dir, "train_*.jpg")),
        key=extract_leading_number
    )

    if not image_files:
        print("Error: No images found.")
        sys.exit(1)

    # Read first image to get dimensions
    testimage = cv2.imread(image_files[0])
    if testimage is None:
        print("Error: Could not read the first image.")
        sys.exit(1)

    h, w, _ = testimage.shape
    print(f"Dimensions: {w}x{h} | FPS: {fps} | GPU Codec: {gpu_codec}")

    output_path = os.path.join(image_dir, output_filename)

    # --- FFmpeg Command for NVIDIA GPU ---
    # We input raw BGR24 data (from OpenCV) -> FFmpeg converts to YUV420P (standard MP4) -> Encodes with GPU
    command = [
        'ffmpeg',
        '-y',                  # Overwrite output file without asking
        '-f', 'rawvideo',      # Input format
        '-vcodec', 'rawvideo',
        '-s', f'{w}x{h}',      # Frame size
        '-pix_fmt', 'bgr24',   # OpenCV provides BGR colors
        '-r', str(fps),        # Input framerate
        '-i', '-',             # Input comes from the pipe (stdin)
        '-c:v', gpu_codec,     # <--- ENABLE NVIDIA GPU ENCODING HERE
        '-pix_fmt', 'yuv420p', # Output color format (needed for video player compatibility)
        '-preset', 'p4',       # NVENC Preset (p1=fastest, p7=highest quality)
        '-b:v', '5M',          # Bitrate (5 Mbps - adjust if needed)
        output_path
    ]

    # Open the FFmpeg subprocess
    try:
        process = subprocess.Popen(command, stdin=subprocess.PIPE, stderr=subprocess.PIPE)
    except FileNotFoundError:
        print("Error: ffmpeg not found. Make sure it is installed and in your PATH.")
        sys.exit(1)

    print(f"Encoding started... writing to {output_filename}")

    count = 0
    for img_path in image_files:
        frame = cv2.imread(img_path)
        
        if frame is None:
            continue

        # Resize if necessary to match the first frame
        if (frame.shape[1] != w) or (frame.shape[0] != h):
            frame = cv2.resize(frame, (w, h))

        # Write raw video data to FFmpeg's stdin
        try:
            process.stdin.write(frame.tobytes())
            count += 1
            # Optional: Print progress every 50 frames
            if count % 50 == 0:
                print(f"Processed {count} frames...")
        except BrokenPipeError:
            print("Error: FFmpeg pipe closed unexpectedly. Check parameters.")
            break

    # Close stdin to signal we are done sending data
    process.stdin.close()
    
    # Wait for FFmpeg to finish encoding
    process.wait()

    if process.returncode == 0:
        print(f"\nSuccess! GPU-accelerated video saved to:\n{output_path}")
    else:
        print(f"\nError: FFmpeg finished with errors. Return code: {process.returncode}")
        # Print ffmpeg error log if it failed
        print(process.stderr.read().decode())