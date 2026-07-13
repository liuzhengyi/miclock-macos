#include <arpa/inet.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

static int append_chunk(FILE *output, const char type[4], const char *path) {
    FILE *input = fopen(path, "rb");
    if (!input) return 0;
    if (fseek(input, 0, SEEK_END) != 0) return 0;
    long size = ftell(input);
    if (size < 0 || fseek(input, 0, SEEK_SET) != 0) return 0;

    uint32_t chunk_length = htonl((uint32_t)size + 8);
    if (fwrite(type, 1, 4, output) != 4 ||
        fwrite(&chunk_length, 1, 4, output) != 4) return 0;

    char buffer[65536];
    size_t count;
    while ((count = fread(buffer, 1, sizeof(buffer), input)) > 0) {
        if (fwrite(buffer, 1, count, output) != count) return 0;
    }
    fclose(input);
    return 1;
}
int main(int argc, char **argv) {
    // output.icns followed by PNG files at 16, 32, 64, 128, 256, 512, 1024.
    if (argc != 9) {
        fprintf(stderr, "usage: create_icns output.icns 16.png 32.png 64.png 128.png 256.png 512.png 1024.png\n");
        return 2;
    }
    const char *types[] = {"icp4", "icp5", "icp6", "ic07", "ic08", "ic09", "ic10"};
    FILE *output = fopen(argv[1], "wb+");
    if (!output) return 1;

    uint32_t placeholder = 0;
    fwrite("icns", 1, 4, output);
    fwrite(&placeholder, 1, 4, output);
    for (int i = 0; i < 7; i++) {
        if (!append_chunk(output, types[i], argv[i + 2])) {
            fclose(output);
            return 1;
        }
    }

    long total = ftell(output);
    if (total < 8 || fseek(output, 4, SEEK_SET) != 0) {
        fclose(output);
        return 1;
    }
    uint32_t total_be = htonl((uint32_t)total);
    fwrite(&total_be, 1, 4, output);
    fclose(output);
    return 0;
}
