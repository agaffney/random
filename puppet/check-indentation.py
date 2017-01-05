#!/usr/bin/python

import sys
import re

stack = []
line_num = 0
in_quote = None
in_block_comment = False

def scan_line(line):
    global stack, line_num, in_quote, in_block_comment

    errors = []
    # Flag for escape character
    escape = False
    # Flag for comment
    in_comment = False
    # Flag for whether we are inside a multi-line comment at start of line
    in_block_comment_at_start = in_block_comment
    # Flag for whether we are inside a multi-line quote at start of line
    in_quote_at_start = (in_quote is not None)

    indent = re.findall(r'^\s*', line)[0]
    indent_len = len(indent)

    for idx, char in enumerate(line):
        if in_block_comment:
            # Check for end of block comment, if in a block comment
            if char == '*' and (len(line) > (idx + 1)) and line[idx + 1] == '/':
                in_block_comment = False
            continue
        if char == '\\':
            escape = (not escape)
            continue
        if char in ('"', "'"):
            if in_quote is None:
                in_quote = char
            else:
                if in_quote == char:
                    in_quote = None
            continue
        if in_quote:
            continue
        # Check for beginning of block comment
        if char == '/' and (len(line) > (idx + 1)) and line[idx+1] == '*':
            in_block_comment = True
            continue
        if char == '#':
            in_comment = True
            break
        elif char == '{':
            # Check for leading indentation before adding a new stack entry
            if len(stack) > 0 and line_num != stack[-1]['line']:
                if indent_len <= stack[-1]['indent']:
                    errors.append("Line %d should be indented further than line %d with previous opening brace" % (line_num, stack[-1]['line']))

            stack.append( { 'indent': indent_len, 'line': line_num } )
        elif char == '}':
            if len(stack) > 0:
                foo = stack.pop()
                if line_num != foo['line'] and indent_len != foo['indent']:
                    errors.append("Closing brace on line %d does not match indentation of opening brace on line %d" % (line_num, foo['line']))

    # Check leading indentation
    if (len(stack) > 0) and (in_quote is None) and (not in_quote_at_start) and (not in_block_comment) and (not in_block_comment_at_start) and (line_num != stack[-1]['line']):
        if indent_len <= stack[-1]['indent']:
            errors.append("Line %d should be indented further than line %d with previous opening brace" % (line_num, stack[-1]['line']))

    if len(errors) > 0:
        raise Exception(errors)


def main():
    global stack, line_num

    # Check commandline parameters
    if len(sys.argv) != 2:
        print "Usage: check-indentation.py <filename>"
        return 1

    # Open input file
    input_file = None
    try:
        input_file = open(sys.argv[1], 'r')
    except:
        print "Failed to open input file: " + sys.argv[1]
        return 1

    # Process file
    exit_code = 0
    for line in input_file:
        line_num = line_num + 1
        # Ignore empty lines and comments
        if re.search(r'^\s*($|#)', line):
            continue
        # Check for braces
        try:
            scan_line(line)
        except Exception as e:
            print '\n'.join(e.args[0])
            exit_code = 1

    return exit_code


if __name__ == '__main__':
    sys.exit(main())
