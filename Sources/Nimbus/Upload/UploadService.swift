import AppKit
import Foundation

// Uploads images to Imgur (anonymous) and returns the public URL.
// Auto-copies the URL to clipboard if PreferencesManager.autoCopyURL is enabled.
final class UploadService {

    static let shared = UploadService()
    private init() {}

    func upload(image: NSImage, completion: @escaping (Result<String, Error>) -> Void) {
        let clientID = PreferencesManager.shared.imgurClientID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clientID.isEmpty else {
            completion(.failure(UploadError.missingClientID))
            return
        }

        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            completion(.failure(UploadError.imageEncodingFailed))
            return
        }

        let base64 = png.base64EncodedString()

        var request = URLRequest(url: URL(string: "https://api.imgur.com/3/image")!)
        request.httpMethod = "POST"
        request.setValue("Client-ID \(clientID)", forHTTPHeaderField: "Authorization")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = "image=\(base64)&type=base64".data(using: .utf8)

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }

            guard let data = data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let dataDict = json["data"] as? [String: Any],
                  let link = dataDict["link"] as? String else {
                completion(.failure(UploadError.invalidResponse))
                return
            }

            let url = link.replacingOccurrences(of: "http://", with: "https://")

            if PreferencesManager.shared.autoCopyURL {
                DispatchQueue.main.async {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(url, forType: .string)
                }
            }

            completion(.success(url))
        }.resume()
    }

    enum UploadError: LocalizedError {
        case imageEncodingFailed
        case invalidResponse
        case missingClientID

        var errorDescription: String? {
            switch self {
            case .imageEncodingFailed: return "Failed to encode image"
            case .invalidResponse:    return "Invalid server response"
            case .missingClientID:    return "No Imgur client ID configured. Set it in Nimbus Preferences (register free at api.imgur.com)."
            }
        }
    }
}
