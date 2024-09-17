package scan
import "core:fmt"
import "core:strings"
import "core:strconv"
import "core:c/libc"
import "core:math"
import "base:runtime"

read_int_string_at_start :: proc(curr : string) -> string
{
    ans := "";
    for i in 0..<len(curr)
    {
        if ('0' <= curr[i] && curr[i] <= '9') || (i == 0 && curr[i] == '-')
        {
            ans = curr[0:(i + 1)]
        }
        else
        {
            break
        }
    }
    return ans
}

read_float_string_at_start :: proc(curr : string) -> string
{
    ans := "";
    for i in 0..<len(curr)
    {
        if ('0' <= curr[i] && curr[i] <= '9') || (i == 0 && curr[i] == '-') || (curr[i] == '.')
        {
            ans = curr[0:(i + 1)]
        }
        else
        {
            break
        }
    }
    return ans
}

scan :: proc(source : string, args: ..any) -> bool
{
    curr := source

    for arg in args
    {
        switch v in arg
        {
            case string:
            {
                if strings.starts_with(curr, v)
                {
                    curr = curr[len(v):]
                    continue
                }
                else
                {
                    panic("string does not match")
                }
            }
            case ^u64:
            {
                number_string := read_int_string_at_start(curr)
                curr = curr[len(number_string):]
                value_parsed, ok := strconv.parse_u64(number_string)
                if !ok { return false }
                v^ = value_parsed
            }
            case ^u32:
            {
                number_string := read_int_string_at_start(curr)
                curr = curr[len(number_string):]
                value_parsed, ok := strconv.parse_u64(number_string)
                if !ok { return false }
                if !(value_parsed < u64(libc.UINT32_MAX)) { return false }
                v^ = u32(value_parsed)
            }
            case ^u16:
            {
                number_string := read_int_string_at_start(curr)
                curr = curr[len(number_string):]
                value_parsed, ok := strconv.parse_u64(number_string)
                if !ok { return false }
                if !(value_parsed < u64(libc.UINT16_MAX)) { return false }
                v^ = u16(value_parsed)
            }
            case ^u8:
            {
                number_string := read_int_string_at_start(curr)
                curr = curr[len(number_string):]
                value_parsed, ok := strconv.parse_u64(number_string)
                if !ok { return false }
                if !(value_parsed < u64(libc.UINT8_MAX)) { return false }
                v^ = u8(value_parsed)
            }
            case ^i64:
            {
                number_string := read_int_string_at_start(curr)
                curr = curr[len(number_string):]
                value_parsed, ok := strconv.parse_i64(number_string)
                if !ok { return false }
                v^ = value_parsed
            }
            case ^i32:
            {
                number_string := read_int_string_at_start(curr)
                curr = curr[len(number_string):]
                value_parsed, ok := strconv.parse_i64(number_string)
                if !ok { return false }
                if !(i64(libc.INT32_MIN) < value_parsed && value_parsed < i64(libc.INT32_MAX)) { return false }
                v^ = i32(value_parsed)
            }
            case ^i16:
            {
                number_string := read_int_string_at_start(curr)
                curr = curr[len(number_string):]
                value_parsed, ok := strconv.parse_i64(number_string)
                if !ok { return false }
                if !(i64(libc.INT16_MIN) < value_parsed && value_parsed < i64(libc.INT16_MAX)) { return false }
                v^ = i16(value_parsed)
            }
            case ^i8:
            {
                number_string := read_int_string_at_start(curr)
                curr = curr[len(number_string):]
                value_parsed, ok := strconv.parse_i64(number_string)
                if !ok { return false }
                if !(i64(libc.INT8_MIN) < value_parsed && value_parsed < i64(libc.INT8_MAX)) { return false }
                v^ = i8(value_parsed)
            }
            case ^f64:
            {
                number_string := read_float_string_at_start(curr)
                curr = curr[len(number_string):]
                value_parsed, ok := strconv.parse_f64(number_string)
                if !ok { return false }
                v^ = value_parsed
            }
            case ^f32:
            {
                number_string := read_float_string_at_start(curr)
                curr = curr[len(number_string):]
                value_parsed, ok := strconv.parse_f64(number_string)
                if !ok { return false }
                v^ = f32(value_parsed)
            }
            case ^f16:
            {
                number_string := read_float_string_at_start(curr)
                curr = curr[len(number_string):]
                value_parsed, ok := strconv.parse_f64(number_string)
                if !ok { return false }
                v^ = f16(value_parsed)
            }
            case ^string:
            {
                v^ = curr
                curr = ""
            }
            case:
            {
                return false
            }
        }
    }
    if curr != ""
    {
        return false
    }
    else
    {
        return true
    }
}
