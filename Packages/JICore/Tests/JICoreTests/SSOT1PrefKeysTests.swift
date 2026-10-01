import Testing
import JICore

// W-SSOT-1 SS-6 (audit 01-P7): the last-upload App-Group key lives once, in JICore.
@Test func hkLastUploadSuccessKeyIsTheUploaderRecord() {
    #expect(PrefKeys.hkLastUploadSuccess == "hk.upload.lastSuccess")
}
