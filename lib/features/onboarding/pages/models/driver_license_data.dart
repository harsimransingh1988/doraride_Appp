class DriverLicenseData {
  final Uint8List? frontImageBytes;
  final Uint8List? backImageBytes;
  final String? licenseName;
  final String? licenseNumber;
  final String? fileNameFront;
  final String? fileNameBack;

  const DriverLicenseData({
    this.frontImageBytes,
    this.backImageBytes,
    this.licenseName,
    this.licenseNumber,
    this.fileNameFront,
    this.fileNameBack,
  });

  DriverLicenseData copyWith({
    Uint8List? frontImageBytes,
    Uint8List? backImageBytes,
    String? licenseName,
    String? licenseNumber,
    String? fileNameFront,
    String? fileNameBack,
  }) {
    return DriverLicenseData(
      frontImageBytes: frontImageBytes ?? this.frontImageBytes,
      backImageBytes: backImageBytes ?? this.backImageBytes,
      licenseName: licenseName ?? this.licenseName,
      licenseNumber: licenseNumber ?? this.licenseNumber,
      fileNameFront: fileNameFront ?? this.fileNameFront,
      fileNameBack: fileNameBack ?? this.fileNameBack,
    );
  }

  bool get isComplete {
    return frontImageBytes != null &&
        backImageBytes != null &&
        licenseName != null &&
        licenseName!.isNotEmpty &&
        licenseNumber != null &&
        licenseNumber!.isNotEmpty;
  }
}