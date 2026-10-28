/**
 * SecureStorage - 敏感信息加解密工具
 * 使用 AES-128-CBC-PKCS7 对称加密，对存储前的敏感字段（密码/Token）加密，读取后解密
 * 密钥为应用内置固定密钥（本工具仅用于混淆存储，防明文落盘）
 */
import { cryptoFramework } from '@kit.CryptoArchitectureKit'
import { hilog } from '@kit.PerformanceAnalysisKit'
import { util } from '@kit.ArkTS'

const TAG = 'SecureStorage'
const DOMAIN = 0x0001

// 固定 16 字节密钥（AES-128）。仅做本地混淆，如需更高安全可改为从用户口令派生
const KEY_BYTES: number[] = [0x69, 0x53, 0x74, 0x6F, 0x72, 0x65, 0x2D, 0x53, 0x65, 0x63, 0x72, 0x65, 0x74, 0x2D, 0x4B, 0x65]
// 固定 16 字节 IV
const IV_BYTES: number[] = [0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x0E, 0x0F]

/** ArkTS 中构造 ParamsSpec 需要类实现接口 */
class IvParamsSpecImpl implements cryptoFramework.IvParamsSpec {
  algName: string = 'IvParamsSpec'
  iv: cryptoFramework.DataBlob

  constructor(iv: cryptoFramework.DataBlob) {
    this.iv = iv
  }
}

/** 将 number[] 转为 DataBlob */
function toBlob(bytes: number[]): cryptoFramework.DataBlob {
  const arr = new Uint8Array(bytes.length)
  for (let i = 0; i < bytes.length; i++) {
    arr[i] = bytes[i]
  }
  return { data: arr }
}

/** 将 string 转 Uint8Array */
function strToBytes(s: string): Uint8Array {
  const enc = new util.TextEncoder()
  return enc.encodeInto(s)
}

/** Uint8Array 转 string */
function bytesToStr(bytes: Uint8Array): string {
  const dec = new util.TextDecoder('utf-8')
  return dec.decodeToString(bytes)
}

/** Uint8Array 转 Base64 */
function bytesToBase64(bytes: Uint8Array): string {
  const base64 = new util.Base64Helper()
  return base64.encodeToStringSync(bytes)
}

/** Base64 转 Uint8Array */
function base64ToBytes(b64: string): Uint8Array {
  const base64 = new util.Base64Helper()
  return base64.decodeSync(b64)
}

/**
 * 加密字符串，返回 Base64 编码的密文（带 enc: 前缀标记）
 * @param plain 明文（可为空串）
 * @returns 'enc:' + Base64 密文；失败返回原明文（不阻塞业务）
 */
export function encrypt(plain: string): string {
  if (!plain) return ''
  // 已加密则直接返回，避免重复加密
  if (plain.startsWith('enc:')) {
    return plain
  }
  if (!canIUse('SystemCapability.Security.CryptoFramework')) {
    return plain
  }
  try {
    const gen = cryptoFramework.createSymKeyGenerator('AES128')
    const key = gen.convertKeySync(toBlob(KEY_BYTES))
    const cipher = cryptoFramework.createCipher('AES128|CBC|PKCS7')
    const params = new IvParamsSpecImpl(toBlob(IV_BYTES))
    cipher.initSync(cryptoFramework.CryptoMode.ENCRYPT_MODE, key, params)
    const enc = cipher.updateSync({ data: strToBytes(plain) })
    const final = cipher.doFinalSync(null)
    // 拼接 enc + final 后 Base64
    const combined = new Uint8Array(enc.data.length + final.data.length)
    combined.set(enc.data, 0)
    combined.set(final.data, enc.data.length)
    return 'enc:' + bytesToBase64(combined)
  } catch (e) {
    hilog.error(DOMAIN, TAG, `encrypt err: ${JSON.stringify(e)}`)
    return plain
  }
}

/**
 * 解密 'enc:' 前缀的密文
 * @param encoded 密文（可能带 enc: 前缀，也可能是不加密的旧数据）
 * @returns 明文；非 enc: 前缀或解密失败时原样返回
 */
export function decrypt(encoded: string): string {
  if (!encoded) return ''
  if (!encoded.startsWith('enc:')) {
    return encoded
  }
  if (!canIUse('SystemCapability.Security.CryptoFramework')) {
    return encoded
  }
  try {
    const gen = cryptoFramework.createSymKeyGenerator('AES128')
    const key = gen.convertKeySync(toBlob(KEY_BYTES))
    const cipher = cryptoFramework.createCipher('AES128|CBC|PKCS7')
    const params = new IvParamsSpecImpl(toBlob(IV_BYTES))
    cipher.initSync(cryptoFramework.CryptoMode.DECRYPT_MODE, key, params)
    const input = base64ToBytes(encoded.substring(4))
    const dec = cipher.updateSync({ data: input })
    const final = cipher.doFinalSync(null)
    const combined = new Uint8Array(dec.data.length + final.data.length)
    combined.set(dec.data, 0)
    combined.set(final.data, dec.data.length)
    return bytesToStr(combined)
  } catch (e) {
    hilog.error(DOMAIN, TAG, `decrypt err: ${JSON.stringify(e)}`)
    return encoded
  }
}
