from reaperparser import *
rpp_file = r"projects/Ambience/Ambience.rpp"

parsed_rpp = parse_rpp(rpp_file)

for line, tokens in parsed_rpp:
  print(f"Line: {line}")
  print("Tokens:")
  for token in tokens:
    print(f"{token.get_string()}: {token.get_boolean()}")