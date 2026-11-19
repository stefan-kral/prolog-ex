# gen.py VEKTOREN [max] > vectors.pl
#
# Testvektoren für library(crypto) aus pyca/cryptography_vectors
# (Apache-2.0 oder BSD-3-Clause; die Dateien stammen aus NIST CAVP,
# RFC 4231, RFC 5869, RFC 7748, RFC 8032 und den Tests von OpenSSL und
# BoringSSL) als Prolog-Fakten; max: höchstens so viele je Datei. Dazu
# PBKDF2-HMAC-SHA512 (Python hashlib) und Vielfache auf secp256k1 (hier mit
# Ganzzahlen gerechnet, unabhängig vom Elixir-Code) – dafür gibt es in der
# Sammlung keine Vektoren.
import hashlib, os, sys

root = sys.argv[1]
mx = int(sys.argv[2]) if len(sys.argv) > 2 else 10**9


def blocks(path, by_count=False):
    """Gruppen "Schlüssel = Wert" (Leerzeile oder neuer COUNT trennt; mit
    by_count nur COUNT)"""
    cur = {}
    for line in open(os.path.join(root, path)):
        line = line.strip()
        if not line or line.startswith('#') or line.startswith('['):
            if cur and not line and not by_count:
                yield cur
                cur = {}
            continue
        if '=' not in line:
            continue
        k, v = (x.strip() for x in line.split('=', 1))
        if k == 'COUNT' and cur:
            yield cur
            cur = {}
        cur[k] = v
    if cur:
        yield cur


def q(s):
    return "'" + s + "'"


out = []

for alg, files in [('sha256', ['SHA2/SHA256ShortMsg.rsp', 'SHA2/SHA256LongMsg.rsp']),
                   ('sha384', ['SHA2/SHA384ShortMsg.rsp', 'SHA2/SHA384LongMsg.rsp']),
                   ('sha512', ['SHA2/SHA512ShortMsg.rsp', 'SHA2/SHA512LongMsg.rsp']),
                   ('sha512_256', ['SHA2/SHA512_256ShortMsg.rsp', 'SHA2/SHA512_256LongMsg.rsp']),
                   ('sha3_224', ['SHA3/SHA3_224ShortMsg.rsp', 'SHA3/SHA3_224LongMsg.rsp']),
                   ('sha3_256', ['SHA3/SHA3_256ShortMsg.rsp', 'SHA3/SHA3_256LongMsg.rsp']),
                   ('sha3_384', ['SHA3/SHA3_384ShortMsg.rsp', 'SHA3/SHA3_384LongMsg.rsp']),
                   ('sha3_512', ['SHA3/SHA3_512ShortMsg.rsp', 'SHA3/SHA3_512LongMsg.rsp']),
                   ('blake2b512', ['blake2/blake2b.txt']),
                   ('blake2s256', ['blake2/blake2s.txt']),
                   ('ripemd160', ['ripemd160/ripevectors.txt'])]:
    for f in files:
        n = 0
        for b in blocks(os.path.join('hashes', f)):
            if 'MD' not in b or int(b['Len']) % 8:
                continue
            msg = b['Msg'] if int(b['Len']) else ''
            out.append('hash(%s, %s, %s).' % (alg, q(msg), q(b['MD'])))
            n += 1
            if n >= mx:
                break

for alg in ['sha256', 'sha384', 'sha512']:
    for b in blocks('HMAC/rfc-4231-%s.txt' % alg):
        out.append('hmac(%s, %s, %s, %s).' % (alg, q(b['Key']), q(b['Msg']), q(b['MD'])))

for b in blocks('KDF/rfc-5869-HKDF-SHA256.txt', True):
    out.append('hkdf(sha256, %s, %s, %s, %s, %s).'
               % (q(b['IKM']), q(b.get('salt', '')), q(b.get('info', '')), b['L'], q(b['OKM'])))

BSSL = {'KEY': 'Key', 'NONCE': 'IV', 'IN': 'Plaintext', 'AD': 'AAD', 'CT': 'Ciphertext', 'TAG': 'Tag'}


def hexval(v):  # BoringSSL: auch "Text" in Anführungszeichen
    return v[1:-1].encode().hex() if v.startswith('"') else v


n = 0
for f in ['openssl.txt', 'boringssl.txt']:
    for b0 in blocks(os.path.join('ciphers/ChaCha20Poly1305', f)):
        b = {BSSL.get(k, k): hexval(v) for k, v in b0.items()}
        if len(b.get('IV', '')) != 24 or len(b.get('Key', '')) != 64 or len(b.get('Tag', '')) != 32:
            continue
        ok = 'fail' if b.get('Result') == 'CIPHERFINAL_ERROR' else 'ok'
        out.append('aead(%s, %s, %s, %s, %s, %s, %s).'
                   % (q(b['Key']), q(b['IV']), q(b.get('AAD', '')), q(b.get('Plaintext', '')),
                      q(b.get('Ciphertext', '')), q(b['Tag']), ok))
        n += 1
        if n >= mx:
            break

n = 0
for line in open(os.path.join(root, 'asymmetric/Ed25519/sign.input')):
    sk, pk, msg, sm, _ = line.strip().split(':')
    out.append('ed25519(%s, %s, %s, %s).' % (q(sk[:64]), q(pk), q(msg), q(sm[:128])))
    n += 1
    if n >= mx:
        break

for b in blocks('asymmetric/X25519/rfc7748.txt'):
    if 'INPUT_SCALAR' in b:
        out.append('x25519(%s, %s, %s).' % (q(b['INPUT_SCALAR']), q(b['INPUT_U']), q(b['OUTPUT_U'])))

for pw, salt, it in [(b'password', b'salt', 1), (b'password', b'salt', 2), (b'password', b'salt', 4096),
                     (b'passwordPASSWORDpassword', b'saltSALTsaltSALTsaltSALTsaltSALTsalt', 4096),
                     (b'pass\0word', b'sa\0lt', 4096), (b'', b'', 1), (b'pw', bytes(range(16)), 131072)]:
    out.append('pbkdf2(%s, %s, %d, %s).'
               % (q(pw.hex()), q(salt.hex()), it, q(hashlib.pbkdf2_hmac('sha512', pw, salt, it, 64).hex())))

# secp256k1: Vielfache des Erzeugers, affine Koordinaten, Lehrbuchformeln
P = 2**256 - 2**32 - 977
N = 0xfffffffffffffffffffffffffffffffebaaedce6af48a03bbfd25e8cd0364141
G = (0x79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798,
     0x483ada7726a3c4655da4fbfc0e1108a8fd17b448a68554199c47d08ffb10d4b8)


def add(a, b):
    if a is None: return b
    if b is None: return a
    if a[0] == b[0] and (a[1] + b[1]) % P == 0: return None
    if a == b:
        l = 3 * a[0] * a[0] * pow(2 * a[1], P - 2, P) % P
    else:
        l = (b[1] - a[1]) * pow(b[0] - a[0], P - 2, P) % P
    x = (l * l - a[0] - b[0]) % P
    return (x, (l * (a[0] - x) - a[1]) % P)


def mul(k, pt):
    r = None
    while k:
        if k & 1: r = add(r, pt)
        pt = add(pt, pt)
        k >>= 1
    return r


for k in [1, 2, 3, 7, 10, 12, 255, 256, 2**64 + 1, 2**128 - 3, N - 2, N - 1, 2**200 + 12345,
          0xfedcba9876543210fedcba9876543210fedcba9876543210fedcba9876543210 % N]:
    r = mul(k, G)
    out.append('secp256k1(%d, %d, %d).' % (k, r[0], r[1]))
# ein anderer Punkt als Basis
B = mul(31337, G)
for k in [2, 1000003, N - 1]:
    r = mul(k, B)
    out.append('secp256k1_at(%d, %d, %d, %d, %d).' % (B[0], B[1], k, r[0], r[1]))

print('% erzeugt von conformance/crypto_vectors/gen.py – nicht von Hand ändern')
print('\n'.join(out))
