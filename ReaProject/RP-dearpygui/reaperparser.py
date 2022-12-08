def is_white_space(c):
  return c == ' ' or c == '\t' or c == '\n'

def trim(s):
  return s.strip()

def is_instance_of(subject, super):
  return isinstance(subject, super)

def split_multiline_str_to_tab(str):
  return str.split("\n")

class RToken:
  def __init__(self, token=None):
    self.token = token

  def get_string(self):
    return self.token

  def get_number(self):
    return float(self.token) if "." in self.token else int(self.token)

  def get_boolean(self):
    return self.token != "0"

  def set_string(self, token):
    self.token = str(token)

  def set_number(self, token):
    self.token = str(token)

  def set_boolean(self, b):
    self.token = "1" if b else "0"

  def to_safe_string(self, s):
    if not s or len(s) == 0:
      return "\"\""
    elif " " in s:
      if "\"" in s:
        if "'" in s:
          s = s.replace("`", "'")
          return "`" + s + "`"
        else:
          return "'" + s + "'"
      else:
        return "\"" + s + "\""
    else:
      return s

def tokenize(line):
  index = 0
  tokens = []
  current_token = ""
  in_string = False
  current_char = line[index]

  while current_char != "":
    if current_char == "\"" or current_char == "'":
      if in_string and current_char == current_token[0]:
        current_token += current_char
        tokens.append(current_token)
        current_token = ""
        in_string = False
      else:
        in_string = True
        current_token += current_char
    elif is_white_space(current_char) and not in_string:
      if current_token != "":
        tokens.append(current_token)
        current_token = ""
    else:
      current_token += current_char

    index += 1
    current_char = line[index] if index < len(line) else ""

  if current_token != "":
    tokens.append(current_token)

  return tokens

def parse_rpp_line(line, tokens):
  token_index = 0

  # Skip the first token if it's a tag
  if tokens[0][0] == "<":
    token_index = 1

  result = []
  current_token = tokens[token_index]
  token_index += 1

  while token_index <= len(tokens):
    if current_token[0] == "<":
      result.append(RToken())
      result[-1].set_string(current_token)
      current_token = tokens[token_index] if token_index < len(tokens) else ""
      token_index += 1
    elif current_token[0] == "\"" or current_token[0] == "'":
      result.append(RToken())
      result[-1].set_string(current_token[1:-1])
      current_token = tokens[token_index] if token_index < len(tokens) else ""
      token_index += 1
    elif current_token == "true" or current_token == "false":
      result.append(RToken())
      result[-1].set_boolean(current_token == "true")
      current_token = tokens[token_index] if token_index < len(tokens) else ""
      token_index += 1
    else:
      try:
        result.append(RToken())
        result[-1].set_number(float(current_token))
        current_token = tokens[token_index] if token_index < len(tokens) else ""
        token_index += 1
      except ValueError:
        result.append(RToken())
        result[-1].set_string(current_token)
        current_token = tokens[token_index] if token_index < len(tokens) else ""
        token_index += 1

  return result

def parse_rpp(rpp_file):
  result = []
  lines = split_multiline_str_to_tab(rpp_file)

  for line in lines:
    line = trim(line)
    tokens = tokenize(line)
    result.append((line, tokens))

  return result
