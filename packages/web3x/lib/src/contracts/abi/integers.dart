import 'dart:typed_data';

import '../../../credentials.dart';
import '../../../web3x.dart' show LengthTrackingByteSink;
import '../../crypto/formatting.dart';
import 'types.dart';

abstract class _IntTypeBase extends AbiType<BigInt> {
  const _IntTypeBase(this.length)
      : assert(length % 8 == 0),
        assert(0 < length && length <= 256);

  /// The length of this uint, int bits. Must be a multiple of 8.
  final int length;

  @override
  EncodingLengthInfo get encodingLength =>
      const EncodingLengthInfo(sizeUnitBytes);

  String get _namePrefix;

  @override
  String get name => _namePrefix + length.toString();

  void validate() {
    if (length % 8 != 0 || length < 0 || length > 256) {
      throw Exception('Invalid length for int type: was $length');
    }
  }

  @override
  DecodingResult<BigInt> decode(ByteBuffer buffer, int offset) {
    // we're always going to read a 32-byte block for integers
    if (buffer.lengthInBytes == 0) {
      buffer = Uint8List(32).buffer;
    }
    return DecodingResult(
      _decode32Bytes(buffer.asUint8List(offset, sizeUnitBytes)),
      sizeUnitBytes,
    );
  }

  BigInt _decode32Bytes(Uint8List data);

  @override
  String toString() {
    return '$runtimeType(length = $length)';
  }
}

/// The solidity uint&lt;M&rt; type that encodes unsigned integers.
class UintType extends _IntTypeBase {
  /// Constructor.
  const UintType({int length = 256}) : super(length);

  @override
  String get _namePrefix => 'uint';

  @override
  void encode(BigInt data, LengthTrackingByteSink buffer) {
    assert(data < BigInt.one << length);
    assert(!data.isNegative);

    final bytes = unsignedIntToBytes(data);
    final padLen = calculatePadLength(bytes.length);
    buffer
      ..add(Uint8List(padLen)) // will be filled with 0
      ..add(bytes);
  }

  /// Encode Replace.
  void encodeReplace(
    int startIndex,
    BigInt data,
    LengthTrackingByteSink buffer,
  ) {
    final bytes = unsignedIntToBytes(data);
    final padLen = calculatePadLength(bytes.length);

    buffer
      ..setRange(startIndex, startIndex + padLen, Uint8List(padLen))
      ..setRange(startIndex + padLen, startIndex + sizeUnitBytes, bytes);
  }

  @override
  BigInt _decode32Bytes(Uint8List data) {
    // The padded zeroes won't make a difference when parsing so we can ignore
    // them.
    return bytesToUnsignedInt(data);
  }

  @override
  int get hashCode => 31 * length;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is UintType && other.length == length);
  }
}

/// Solidity address type
class AddressType extends AbiType<EthereumAddress> {
  /// Constructor.
  const AddressType();

  static const _paddingLen = sizeUnitBytes - EthereumAddress.addressByteLength;

  @override
  EncodingLengthInfo get encodingLength =>
      const EncodingLengthInfo(sizeUnitBytes);

  @override
  String get name => 'address';

  @override
  void encode(EthereumAddress data, LengthTrackingByteSink buffer) {
    buffer
      ..add(Uint8List(_paddingLen))
      ..add(data.addressBytes);
  }

  @override
  DecodingResult<EthereumAddress> decode(ByteBuffer buffer, int offset) {
    final addressBytes = buffer.asUint8List(
      offset + _paddingLen,
      EthereumAddress.addressByteLength,
    );
    return DecodingResult(EthereumAddress(addressBytes), sizeUnitBytes);
  }

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  bool operator ==(Object other) {
    return other.runtimeType == AddressType;
  }
}

/// Solidity bool type
class BoolType extends AbiType<bool> {
  /// Constructor.
  const BoolType();

  static final Uint8List _false = Uint8List(sizeUnitBytes);
  static final Uint8List _true = Uint8List(sizeUnitBytes)
    ..[sizeUnitBytes - 1] = 1;

  @override
  EncodingLengthInfo get encodingLength =>
      const EncodingLengthInfo(sizeUnitBytes);

  @override
  String get name => 'bool';

  @override
  void encode(bool data, LengthTrackingByteSink buffer) {
    buffer.add(data ? _true : _false);
  }

  @override
  DecodingResult<bool> decode(ByteBuffer buffer, int offset) {
    final decoded = buffer.asUint8List(offset, sizeUnitBytes);
    final value = (decoded[sizeUnitBytes - 1] & 1) == 1;

    return DecodingResult(value, sizeUnitBytes);
  }

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  bool operator ==(Object other) {
    return other.runtimeType == BoolType;
  }
}

/// The solidity int&lt;M&rt; types that encodes twos-complement integers.
class IntType extends _IntTypeBase {
  /// Constructor.
  const IntType({int length = 256}) : super(length);

  @override
  String get _namePrefix => 'int';

  @override
  void encode(BigInt data, LengthTrackingByteSink buffer) {
    final negative = data.isNegative;
    Uint8List bytesData;

    if (negative) {
      // twos complement
      bytesData = unsignedIntToBytes((BigInt.one << length) + data);
    } else {
      bytesData = unsignedIntToBytes(data);
    }

    final padLen = calculatePadLength(bytesData.length);

    // signed expansion: use 0b11111111 when negative, 0 otherwise
    if (negative) {
      buffer.add(List.filled(padLen, 0xFF));
    } else {
      buffer.add(Uint8List(padLen)); // will be filled with zeroes
    }

    buffer.add(bytesData);
  }

  @override
  BigInt _decode32Bytes(Uint8List data) {
    return bytesToInt(data);
  }

  @override
  int get hashCode => 37 * length;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        (other is IntType && other.length == length);
  }
}
