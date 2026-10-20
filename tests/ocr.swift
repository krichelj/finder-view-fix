// Prints every text line Apple's Vision OCR finds in an image (argv[1]).
import Foundation
import Vision
let url = URL(fileURLWithPath: CommandLine.arguments[1])
let req = VNRecognizeTextRequest()
req.recognitionLevel = .accurate
try VNImageRequestHandler(url: url).perform([req])
for o in req.results ?? [] { if let t = o.topCandidates(1).first { print(t.string) } }
