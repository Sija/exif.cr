lib LibEXIF
  # EXIF tags (identifiers of entries)
  enum EXIFTag
    InteroperabilityIndex               = 0x0001
    InteroperabilityVersion             = 0x0002
    NewSubfileType                      = 0x00fe
    ImageWidth                          = 0x0100
    ImageLength                         = 0x0101
    BitsPerSample                       = 0x0102
    Compression                         = 0x0103
    PhotometricInterpretation           = 0x0106
    FillOrder                           = 0x010a
    DocumentName                        = 0x010d
    ImageDescription                    = 0x010e
    Make                                = 0x010f
    Model                               = 0x0110
    StripOffsets                        = 0x0111
    Orientation                         = 0x0112
    SamplesPerPixel                     = 0x0115
    RowsPerStrip                        = 0x0116
    StripByteCounts                     = 0x0117
    XResolution                         = 0x011a
    YResolution                         = 0x011b
    PlanarConfiguration                 = 0x011c
    ResolutionUnit                      = 0x0128
    TransferFunction                    = 0x012d
    Software                            = 0x0131
    DateTime                            = 0x0132
    Artist                              = 0x013b
    WhitePoint                          = 0x013e
    PrimaryChromaticities               = 0x013f
    SubIFDs                             = 0x014a
    TransferRange                       = 0x0156
    JPEGProc                            = 0x0200
    JPEGInterchangeFormat               = 0x0201
    JPEGInterchangeFormatLength         = 0x0202
    YCbCrCoefficients                   = 0x0211
    YCbCrSubSampling                    = 0x0212
    YCbCrPositioning                    = 0x0213
    ReferenceBlackWhite                 = 0x0214
    XMLPacket                           = 0x02bc
    RelatedImageFileFormat              = 0x1000
    RelatedImageWidth                   = 0x1001
    RelatedImageLength                  = 0x1002
    ImageDepth                          = 0x80e5
    CFARepeatPatternDim                 = 0x828d
    CFAPattern                          = 0x828e
    BatteryLevel                        = 0x828f
    Copyright                           = 0x8298
    ExposureTime                        = 0x829a
    FNumber                             = 0x829d
    IPTCNAA                             = 0x83bb
    ImageResources                      = 0x8649
    EXIFIfdPointer                      = 0x8769
    InterColorProfile                   = 0x8773
    ExposureProgram                     = 0x8822
    SpectralSensitivity                 = 0x8824
    GPSInfoIfdPointer                   = 0x8825
    ISOSpeedRatings                     = 0x8827
    OECF                                = 0x8828
    TimeZoneOffset                      = 0x882a
    SensitivityType                     = 0x8830
    StandardOutputSensitivity           = 0x8831
    RecommendedExposureIndex            = 0x8832
    ISOSpeed                            = 0x8833
    ISOSpeedLatitudeYYY                 = 0x8834
    ISOSpeedLatitudeZZZ                 = 0x8835
    EXIFVersion                         = 0x9000
    DateTimeOriginal                    = 0x9003
    DateTimeDigitized                   = 0x9004
    OffsetTime                          = 0x9010
    OffsetTimeOriginal                  = 0x9011
    OffsetTimeDigitized                 = 0x9012
    ComponentsConfiguration             = 0x9101
    CompressedBitsPerPixel              = 0x9102
    ShutterSpeedValue                   = 0x9201
    ApertureValue                       = 0x9202
    BrightnessValue                     = 0x9203
    ExposureBiasValue                   = 0x9204
    MaxApertureValue                    = 0x9205
    SubjectDistance                     = 0x9206
    MeteringMode                        = 0x9207
    LightSource                         = 0x9208
    Flash                               = 0x9209
    FocalLength                         = 0x920a
    SubjectArea                         = 0x9214
    TIFFEPStandardID                    = 0x9216
    MakerNote                           = 0x927c
    UserComment                         = 0x9286
    SubSecTime                          = 0x9290
    SubSecTimeOriginal                  = 0x9291
    SubSecTimeDigitized                 = 0x9292
    XPTitle                             = 0x9c9b
    XPComment                           = 0x9c9c
    XPAuthor                            = 0x9c9d
    XPKeywords                          = 0x9c9e
    XPSubject                           = 0x9c9f
    FlashpixVersion                     = 0xa000
    ColorSpace                          = 0xa001
    PixelXDimension                     = 0xa002
    PixelYDimension                     = 0xa003
    RelatedSoundFile                    = 0xa004
    InteroperabilityIfdPointer          = 0xa005
    FlashEnergy                         = 0xa20b
    SpatialFrequencyResponse            = 0xa20c
    FocalPlaneXResolution               = 0xa20e
    FocalPlaneYResolution               = 0xa20f
    FocalPlaneResolutionUnit            = 0xa210
    SubjectLocation                     = 0xa214
    ExposureIndex                       = 0xa215
    SensingMethod                       = 0xa217
    FileSource                          = 0xa300
    SceneType                           = 0xa301
    NewCFAPattern                       = 0xa302
    CustomRendered                      = 0xa401
    ExposureMode                        = 0xa402
    WhiteBalance                        = 0xa403
    DigitalZoomRatio                    = 0xa404
    FocalLengthIn35mmFilm               = 0xa405
    SceneCaptureType                    = 0xa406
    GainControl                         = 0xa407
    Contrast                            = 0xa408
    Saturation                          = 0xa409
    Sharpness                           = 0xa40a
    DeviceSettingDescription            = 0xa40b
    SubjectDistanceRange                = 0xa40c
    ImageUniqueID                       = 0xa420
    CameraOwnerName                     = 0xa430
    BodySerialNumber                    = 0xa431
    LensSpecification                   = 0xa432
    LensMake                            = 0xa433
    LensModel                           = 0xa434
    LensSerialNumber                    = 0xa435
    CompositeImage                      = 0xa460
    SourceImageNumberOfCompositeImage   = 0xa461
    SourceExposureTimesOfCompositeImage = 0xa462
    Gamma                               = 0xa500
    PrintImageMatching                  = 0xc4a5
    Padding                             = 0xea1c
  end

  # GPS tags (these overlap numerically with `EXIFTag` and are only valid in the GPS IFD)
  enum EXIFGPSTag
    GPSVersionID         = 0x0000
    GPSLatitudeRef       = 0x0001
    GPSLatitude          = 0x0002
    GPSLongitudeRef      = 0x0003
    GPSLongitude         = 0x0004
    GPSAltitudeRef       = 0x0005
    GPSAltitude          = 0x0006
    GPSTimeStamp         = 0x0007
    GPSSatellites        = 0x0008
    GPSStatus            = 0x0009
    GPSMeasureMode       = 0x000a
    GPSDOP               = 0x000b
    GPSSpeedRef          = 0x000c
    GPSSpeed             = 0x000d
    GPSTrackRef          = 0x000e
    GPSTrack             = 0x000f
    GPSImgDirectionRef   = 0x0010
    GPSImgDirection      = 0x0011
    GPSMapDatum          = 0x0012
    GPSDestLatitudeRef   = 0x0013
    GPSDestLatitude      = 0x0014
    GPSDestLongitudeRef  = 0x0015
    GPSDestLongitude     = 0x0016
    GPSDestBearingRef    = 0x0017
    GPSDestBearing       = 0x0018
    GPSDestDistanceRef   = 0x0019
    GPSDestDistance      = 0x001a
    GPSProcessingMethod  = 0x001b
    GPSAreaInformation   = 0x001c
    GPSDateStamp         = 0x001d
    GPSDifferential      = 0x001e
    GPSHPositioningError = 0x001f
  end

  # What level of support a tag enjoys in the EXIF standard
  enum EXIFSupportLevel
    # The meaning of this tag is unknown
    Unknown = 0
    # This tag is not allowed in the given IFD
    NotRecorded
    # This tag is mandatory in the given IFD
    Mandatory
    # This tag is optional in the given IFD
    Optional
  end

  fun exif_tag_from_name(name : LibC::Char*) : EXIFTag
  fun exif_tag_get_name_in_ifd(tag : EXIFTag, ifd : EXIFIfd) : LibC::Char*
  fun exif_tag_get_title_in_ifd(tag : EXIFTag, ifd : EXIFIfd) : LibC::Char*
  fun exif_tag_get_description_in_ifd(tag : EXIFTag, ifd : EXIFIfd) : LibC::Char*
  fun exif_tag_get_support_level_in_ifd(tag : EXIFTag, ifd : EXIFIfd, t : EXIFDataType) : EXIFSupportLevel

  fun exif_tag_get_name(tag : EXIFTag) : LibC::Char*
  fun exif_tag_get_title(tag : EXIFTag) : LibC::Char*
  fun exif_tag_get_description(tag : EXIFTag) : LibC::Char*

  fun exif_tag_table_get_tag(n : LibC::UInt) : EXIFTag
  fun exif_tag_table_get_name(n : LibC::UInt) : LibC::Char*
  fun exif_tag_table_count : LibC::UInt
end
