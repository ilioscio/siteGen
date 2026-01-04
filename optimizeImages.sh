#!/usr/bin/env nix-shell
#! nix-shell -i bash -p imagemagick jpegoptim optipng coreutils

# This script requires nix.

# Variable to track total space saved
total_space_saved=0

# Function to convert bytes to human-readable format
human_readable_size() {
    local bytes="$1"
    local -a units=("B" "KB" "MB" "GB")
    local size="$bytes"
    local unit=0

    # Convert to more readable units
    while [ "$size" -ge 1024 ] && [ $unit -lt 3 ]; do
        size=$((size / 1024))
        ((unit++))
    done

    echo "$size ${units[$unit]}"
}

# Function to process PNG files
process_png() {
    local file="$1"
    local filename
    local dirname
    local basename
    local orig_file
    local temp_file
    local orig_size
    local new_size
    local space_saved

    # Extract full path components
    filename=$(basename "$file")
    dirname=$(dirname "$file")

    # Remove .orig from filename if present
    if [[ "$filename" == *.orig.png ]]; then
        return
    fi

    # Extract basename without extension
    basename="${filename%.*}"
    orig_file="${dirname}/${basename}.orig.png"
    temp_file="${dirname}/${basename}_temp.png"

    # Skip if .orig file already exists
    if [[ -f "$orig_file" ]]; then
        return
    fi

    # Get original file size
    orig_size=$(stat -c%s "$file")

    # Copy original to .orig
    cp "$file" "$orig_file"

    # Optimize with optipng to a temp file
    optipng -o7 "$orig_file" -out "$temp_file"

    # Get new file size
    new_size=$(stat -c%s "$temp_file")

    # Compare sizes and replace only if new file is smaller
    if [ "$new_size" -lt "$orig_size" ]; then
        # Calculate space saved
        space_saved=$((orig_size - new_size))
        total_space_saved=$((total_space_saved + space_saved))

        # Replace original with optimized file
        mv "$temp_file" "$file"

        echo "Processed PNG: $file (Saved: $(human_readable_size "$space_saved"))"
    else
        # Remove temp file if no optimization occurred
        rm "$temp_file"
        # Restore original file
        mv "$orig_file" "$file"
        echo "No optimization for PNG: $file"
    fi
}

# Function to process JPG/JPEG files
process_jpg() {
    local file="$1"
    local filename
    local dirname
    local basename
    local orig_file
    local ext
    local orig_size
    local new_size
    local space_saved

    # Extract full path components
    filename=$(basename "$file")
    dirname=$(dirname "$file")
    ext="${filename##*.}"

    # Remove .orig from filename if present
    if [[ "$filename" == *.orig.jpg ]] || [[ "$filename" == *.orig.jpeg ]]; then
        return
    fi

    # Extract basename without extension
    basename="${filename%.*}"
    orig_file="${dirname}/${basename}.orig.${ext}"

    # Skip if .orig file already exists
    if [[ -f "$orig_file" ]]; then
        return
    fi

    # Get original file size
    orig_size=$(stat -c%s "$file")

    # Copy original to .orig
    cp "$file" "$orig_file"

    # Optimize JPEG with maximum compression
    # Use --strip-all to remove metadata
    # Use -m to reduce color quality
    # Progressively lower quality until file size is reduced
    jpegoptim --strip-all -m70 -q "$orig_file" -o "$file"

    # Get new file size
    new_size=$(stat -c%s "$file")

    # Compare sizes and keep original if no optimization occurred
    if [ "$new_size" -lt "$orig_size" ]; then
        # Calculate space saved
        space_saved=$((orig_size - new_size))
        total_space_saved=$((total_space_saved + space_saved))

        echo "Processed JPG: $file (Saved: $(human_readable_size "$space_saved"))"
    else
        # Restore original file if no optimization
        mv "$orig_file" "$file"
        echo "No optimization for JPG: $file"
    fi
}

# Main script logic
if [ $# -eq 0 ]; then
    echo "Usage: $0 <directory>"
    exit 1
fi

# Normalize and validate directory path
directory=$(realpath "$1")

# Validate directory
if [ ! -d "$directory" ]; then
    echo "Error: $1 is not a valid directory"
    exit 1
fi

# Process all PNG files in the directory
shopt -s nullglob
for png in "$directory"/*.png; do
    # Skip if it's an .orig.png file
    [[ "$png" == *.orig.png ]] && continue
    process_png "$png"
done

# Process all JPG and JPEG files in the directory
for jpg in "$directory"/*.jpg "$directory"/*.jpeg; do
    # Skip if it's an .orig.jpg or .orig.jpeg file
    [[ "$jpg" == *.orig.jpg ]] || [[ "$jpg" == *.orig.jpeg ]] && continue
    process_jpg "$jpg"
done
shopt -u nullglob

# Report total space saved
echo "Total space saved: $(human_readable_size "$total_space_saved")"
