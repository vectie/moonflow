///|
/// An algorithm-tagged digest. FLOW-3 accepts exactly lowercase
/// `sha256:<64 lowercase hexadecimal digits>`.
pub struct ContentDigest {
  algorithm : String
  hex : String
} derive(Eq, Compare, Debug)

///|
pub fn ContentDigest::parse(
  value : String,
) -> ContentDigest raise ContractError {
  guard value.split_once(":") is Some((algorithm, hex)) else {
    raise InvalidDigestSyntax(field="digest")
  }
  let algorithm = algorithm.to_owned()
  let hex = hex.to_owned()
  if algorithm.is_empty() {
    raise InvalidDigestSyntax(field="algorithm")
  }
  if algorithm != "sha256" {
    raise UnsupportedDigestAlgorithm(algorithm)
  }
  if hex.length() != 64 ||
    !hex
    .iter()
    .all(char => char.is_ascii_digit() || ('a' <= char && char <= 'f')) {
    raise InvalidDigestSyntax(field="digest")
  }
  { algorithm, hex }
}

///|
pub fn ContentDigest::algorithm(self : ContentDigest) -> String {
  self.algorithm
}

///|
pub fn ContentDigest::hex(self : ContentDigest) -> String {
  self.hex
}

///|
pub fn ContentDigest::text(self : ContentDigest) -> String {
  "\{self.algorithm}:\{self.hex}"
}

///|
let sha256_round_constants : ReadOnlyArray[UInt] = [
  0x428a2f98U, 0x71374491U, 0xb5c0fbcfU, 0xe9b5dba5U, 0x3956c25bU, 0x59f111f1U, 0x923f82a4U,
  0xab1c5ed5U, 0xd807aa98U, 0x12835b01U, 0x243185beU, 0x550c7dc3U, 0x72be5d74U, 0x80deb1feU,
  0x9bdc06a7U, 0xc19bf174U, 0xe49b69c1U, 0xefbe4786U, 0x0fc19dc6U, 0x240ca1ccU, 0x2de92c6fU,
  0x4a7484aaU, 0x5cb0a9dcU, 0x76f988daU, 0x983e5152U, 0xa831c66dU, 0xb00327c8U, 0xbf597fc7U,
  0xc6e00bf3U, 0xd5a79147U, 0x06ca6351U, 0x14292967U, 0x27b70a85U, 0x2e1b2138U, 0x4d2c6dfcU,
  0x53380d13U, 0x650a7354U, 0x766a0abbU, 0x81c2c92eU, 0x92722c85U, 0xa2bfe8a1U, 0xa81a664bU,
  0xc24b8b70U, 0xc76c51a3U, 0xd192e819U, 0xd6990624U, 0xf40e3585U, 0x106aa070U, 0x19a4c116U,
  0x1e376c08U, 0x2748774cU, 0x34b0bcb5U, 0x391c0cb3U, 0x4ed8aa4aU, 0x5b9cca4fU, 0x682e6ff3U,
  0x748f82eeU, 0x78a5636fU, 0x84c87814U, 0x8cc70208U, 0x90befffaU, 0xa4506cebU, 0xbef9a3f7U,
  0xc67178f2U,
]

///|
fn rotate_right(value : UInt, bits : Int) -> UInt {
  (value >> bits) | (value << (32 - bits))
}

///|
fn sha256_words(input : Bytes) -> Array[UInt] {
  let padded = input.to_array()
  padded.push(0x80)
  while padded.length() % 64 != 56 {
    padded.push(0)
  }
  let bit_length = UInt64::extend_uint(input.length().reinterpret_as_uint()) *
    8UL
  padded.push_iter(bit_length.to_be_bytes().iter())
  let state : Array[UInt] = [
    0x6a09e667U, 0xbb67ae85U, 0x3c6ef372U, 0xa54ff53aU, 0x510e527fU, 0x9b05688cU,
    0x1f83d9abU, 0x5be0cd19U,
  ]
  for offset = 0; offset < padded.length(); offset = offset + 64 {
    let words : Array[UInt] = Array::make(64, 0U)
    for index in 0..<16 {
      let base = offset + index * 4
      words[index] = (padded[base].to_uint() << 24) |
        (padded[base + 1].to_uint() << 16) |
        (padded[base + 2].to_uint() << 8) |
        padded[base + 3].to_uint()
    }
    for index in 16..<64 {
      let x = words[index - 15]
      let y = words[index - 2]
      let small0 = rotate_right(x, 7) ^ rotate_right(x, 18) ^ (x >> 3)
      let small1 = rotate_right(y, 17) ^ rotate_right(y, 19) ^ (y >> 10)
      words[index] = words[index - 16] + small0 + words[index - 7] + small1
    }
    let mut a = state[0]
    let mut b = state[1]
    let mut c = state[2]
    let mut d = state[3]
    let mut e = state[4]
    let mut f = state[5]
    let mut g = state[6]
    let mut h = state[7]
    for index in 0..<64 {
      let big1 = rotate_right(e, 6) ^ rotate_right(e, 11) ^ rotate_right(e, 25)
      let choose = (e & f) ^ (e.lnot() & g)
      let temporary1 = h +
        big1 +
        choose +
        sha256_round_constants[index] +
        words[index]
      let big0 = rotate_right(a, 2) ^ rotate_right(a, 13) ^ rotate_right(a, 22)
      let majority = (a & b) ^ (a & c) ^ (b & c)
      let temporary2 = big0 + majority
      h = g
      g = f
      f = e
      e = d + temporary1
      d = c
      c = b
      b = a
      a = temporary1 + temporary2
    }
    state[0] = state[0] + a
    state[1] = state[1] + b
    state[2] = state[2] + c
    state[3] = state[3] + d
    state[4] = state[4] + e
    state[5] = state[5] + f
    state[6] = state[6] + g
    state[7] = state[7] + h
  }
  state
}

///|
/// Pure deterministic SHA-256 over the exact input bytes.
pub fn sha256_hex(input : Bytes) -> String {
  let builder = StringBuilder()
  for word in sha256_words(input) {
    let value = word.to_string(radix=16)
    for _ in value.length()..<8 {
      builder.write_string("0")
    }
    builder.write_string(value)
  }
  builder.to_string()
}

///|
pub fn sha256_digest(input : Bytes) -> ContentDigest {
  { algorithm: "sha256", hex: sha256_hex(input) }
}
