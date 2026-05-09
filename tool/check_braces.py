"""Counts { } depth in a Dart file, ignoring strings/comments."""
import sys

path = r'c:\Users\FRIDAY\OneDrive\Desktop\PDFist\lib\screens\tool_screen.dart'
with open(path, 'r', encoding='utf-8') as f:
    content = f.read()

i = 0
depth = 0
events = []
line_no = 1
n = len(content)

while i < n:
    c = content[i]
    if c == '\n':
        line_no += 1
        i += 1
        continue
    if c == '/' and i+1 < n and content[i+1] == '/':
        while i < n and content[i] != '\n':
            i += 1
        continue
    if c == '/' and i+1 < n and content[i+1] == '*':
        i += 2
        while i < n-1 and not (content[i] == '*' and content[i+1] == '/'):
            if content[i] == '\n': line_no += 1
            i += 1
        i += 2
        continue
    if c in ('"', "'"):
        q = c
        i += 1
        while i < n:
            ch = content[i]
            if ch == '\\': i += 2; continue
            if ch == '\n': line_no += 1
            if ch == q: i += 1; break
            i += 1
        continue
    if c == '{':
        depth += 1
        events.append((line_no, depth, '{'))
    elif c == '}':
        depth -= 1
        events.append((line_no, depth, '}'))
    i += 1

print(f"Final depth: {depth}")
print("\nClass-level opens (depth→1):")
for ln, d, ch in events:
    if ch == '{' and d == 1:
        print(f"  line {ln}")
print("\nClass-level closes (depth→0):")
for ln, d, ch in events:
    if ch == '}' and d == 0:
        print(f"  line {ln}")
print("\nDepth near line 300-310:")
for ln, d, ch in events:
    if 295 <= ln <= 315:
        print(f"  line {ln}: '{ch}' -> depth {d}")
