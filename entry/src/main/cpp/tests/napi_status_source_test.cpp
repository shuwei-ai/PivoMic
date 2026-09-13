#include <cassert>
#include <fstream>
#include <iostream>
#include <iterator>
#include <string>

int main() {
    std::string path = NAPI_INIT_SOURCE;
    std::ifstream input(path);
    if (!input.good()) {
        std::cerr << "Failed to open NAPI_INIT_SOURCE path: " << path << std::endl;
    }
    assert(input.good());
    std::string source((std::istreambuf_iterator<char>(input)), std::istreambuf_iterator<char>());
    assert(source.find("(void)napi_") == std::string::npos);
    return 0;
}
