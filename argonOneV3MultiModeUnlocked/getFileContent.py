import os

# Define the output file
output_file = 'output_python.txt'

# Define the image file extensions to exclude
image_extensions = ('.png', '.xcf')

# Open the output file in write mode
with open(output_file, 'w', encoding='utf-8') as outfile:
    # Walk through the current directory
    for root, _, files in os.walk(os.getcwd()):
        for file in files:
            # Check if the file is not an image
            if not file.endswith(image_extensions):
                file_path = os.path.join(root, file)
                # Open and read the file with a specified encoding
                with open(file_path, 'r', encoding='latin-1') as infile:
                    outfile.write(infile.read())
                    outfile.write("\n")  # Add a newline between files

print("Concatenation complete.")
