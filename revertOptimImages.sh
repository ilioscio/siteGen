#!/usr/bin/env nix-shell
#! nix-shell -i bash -p imagemagick jpegoptim optipng

# Image Reversion Script
# Restores images to their original state by replacing processed files with .orig files
# Only processes .orig files that have a matching non-orig image file

# Function to revert PNG files
revert_png() {
    local orig_file="$1"
    local target_file="${orig_file%.orig.png}.png"

    # Check if a non-orig PNG exists in the same location
    if [[ -f "$target_file" ]]; then
        # Remove the processed file
        rm "$target_file"
        
        # Rename .orig.png back to .png
        mv "$orig_file" "$target_file"
        
        echo "Reverted PNG: $target_file"
    fi
}

# Function to revert JPG/JPEG files
revert_jpg() {
    local orig_file="$1"
    local base_name="${orig_file%.orig.jpg}"
    local base_name_jpeg="${orig_file%.orig.jpeg}"
    local target_jpg="${base_name}.jpg"
    local target_jpeg="${base_name_jpeg}.jpeg"

    # Check if a non-orig JPG or JPEG exists
    if [[ -f "$target_jpg" ]]; then
        # Remove the processed file
        rm "$target_jpg"
        
        # Rename .orig.jpg back to .jpg
        mv "$orig_file" "$target_jpg"
        
        echo "Reverted JPG: $target_jpg"
    elif [[ -f "$target_jpeg" ]]; then
        # Remove the processed file
        rm "$target_jpeg"
        
        # Rename .orig.jpeg back to .jpeg
        mv "$orig_file" "$target_jpeg"
        
        echo "Reverted JPEG: $target_jpeg"
    fi
}

# Main script logic
if [ $# -eq 0 ]; then
    echo "Usage: $0 <directory>"
    exit 1
fi

# Validate directory
if [ ! -d "$1" ]; then
    echo "Error: $1 is not a valid directory"
    exit 1
fi

# Process PNG .orig files
shopt -s nullglob
for orig_png in "$1"/*.orig.png; do
    revert_png "$orig_png"
done

# Process JPG and JPEG .orig files
for orig_jpg in "$1"/*.orig.jpg "$1"/*.orig.jpeg; do
    revert_jpg "$orig_jpg"
done
shopt -u nullglob

echo "Image reversion complete for directory: $1"
