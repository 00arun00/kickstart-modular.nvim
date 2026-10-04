#pragma once
// C++17, header-only formatters. Custom types need operator<< or an overload.
#include <cstdlib>
#include <iostream>
#include <iterator>
#include <sstream>
#include <string>
#include <string_view>
#include <type_traits>
#include <utility>
#if __has_include(<stacktrace>)
#include <stacktrace>
#endif
#if !defined(__cpp_lib_stacktrace) && __has_include(<execinfo.h>)
#include <execinfo.h>
#define NVIM_DBG_EXECINFO 1
#endif
namespace nvim_dbg {
template<class T, class = void> struct is_range : std::false_type {};
template<class T> struct is_range<T, std::void_t<decltype(std::begin(std::declval<const T&>())), decltype(std::end(std::declval<const T&>()))>> : std::true_type {};
template<class T> struct is_pair : std::false_type {};
template<class A, class B> struct is_pair<std::pair<A,B>> : std::true_type {};
inline std::string escaped(std::string_view value) {
    std::string result = "\"";
    const char* digits = "0123456789abcdef";
    for (unsigned char c : value) {
        switch(c) {
            case '\\': result += "\\\\"; break;
            case '"': result += "\\\""; break;
            case '\n': result += "\\n"; break;
            case '\r': result += "\\r"; break;
            case '\t': result += "\\t"; break;
            default:
                if(c < 32 || c == 127) { result += "\\x"; result += digits[c >> 4]; result += digits[c & 15]; }
                else result += static_cast<char>(c);
        }
    }
    return result + "\"";
}
template<class T> std::string repr(const T& value, int depth = 0) {
    if(depth > 8) return "<max depth>";
    if constexpr (std::is_convertible_v<const T&, std::string_view>) {
        if constexpr (std::is_pointer_v<T>) { if(value == nullptr) return "nullptr"; }
        return escaped(std::string_view(value));
    } else if constexpr (std::is_same_v<T,bool>) return value ? "true" : "false";
    else if constexpr (is_pair<T>::value) return repr(value.first,depth+1) + ": " + repr(value.second,depth+1);
    else if constexpr (is_range<T>::value) {
        std::string result = "["; unsigned count = 0;
        for(const auto& item : value) {
            if(count) result += ", ";
            if(count++ == 100) { result += "..."; break; }
            result += repr(item,depth+1);
        }
        return result + "]";
    } else { std::ostringstream stream; stream << value; return stream.str(); }
}
template<class T> void repr_log(const char* marker, const char* label, const T& value) {
    std::cerr << " " << marker << " repr │ " << label << " → " << repr(value) << '\n';
}
template<class T> void object_log(const char* marker, const char* label, const T& value) {
    std::cerr << " " << marker << " object │ " << label << '\n';
    if constexpr (is_range<T>::value && !std::is_convertible_v<const T&,std::string_view>) {
        std::cerr << "    [\n"; unsigned count = 0;
        for(const auto& item : value) { if(count++ == 100) { std::cerr << "        ...\n"; break; } std::cerr << "        " << repr(item) << ",\n"; }
        std::cerr << "    ]\n";
    } else std::cerr << "    " << repr(value) << '\n';
}
template<class T> [[noreturn]] void fail(const char* marker, const char* condition, const T& observed, const char* file, int line) {
    std::cerr << "🧪 " << marker << " assert │ condition failed\n    │\n    │  expected   " << condition
              << "\n    │  observed   " << repr(observed) << "\n    │  location   " << file << ':' << line << "\n    ╰─ FAILED\n";
    std::abort();
}
inline void stack_log(const char* marker) {
    std::cerr << " " << marker << " stack │ native C++ backtrace\n";
#if defined(__cpp_lib_stacktrace) && __cpp_lib_stacktrace >= 202011L
    std::cerr << std::stacktrace::current() << '\n';
#elif defined(NVIM_DBG_EXECINFO)
    void* frames[64]; int count = ::backtrace(frames, 64);
    char** symbols = ::backtrace_symbols(frames, count);
    if(symbols) { for(int i=1;i<count;++i) std::cerr << "    " << symbols[i] << '\n'; std::free(symbols); }
#else
    std::cerr << "    Stack capture unavailable on this toolchain; use the debugger's call stack.\n";
#endif
}
}
