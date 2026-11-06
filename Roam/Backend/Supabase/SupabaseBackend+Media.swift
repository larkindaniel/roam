import CryptoKit
import Foundation

extension SupabaseBackend: MediaService {
    func stage(jpegData: Data, width: Int, height: Int, purpose: MediaPurpose, uploadAttemptID: UUID) async throws -> StagedMedia {
        let snapshot = try await requestSnapshot()
        guard let actor = snapshot.userID else { throw RoamError.notSignedIn }
        let bucket = purpose == .avatar ? "avatars" : "visit-media"
        let path = "\(actor.uuidString.lowercased())/\(uploadAttemptID.uuidString.lowercased()).jpg"
        let digest = SHA256.hash(data: jpegData).map { String(format: "%02x", $0) }.joined()
        do {
            var upload = URLRequest(url: config.supabaseURL.appendingPathComponent("storage/v1/object/\(bucket)/\(path)"))
            upload.httpMethod = "POST"
            upload.httpBody = jpegData
            snapshot.headers.forEach { upload.setValue($0.value, forHTTPHeaderField: $0.key) }
            upload.setValue("image/jpeg", forHTTPHeaderField: "Content-Type")
            upload.setValue("false", forHTTPHeaderField: "x-upsert")
            let (uploadBody, uploadResponse) = try await send(upload)
            let status = (uploadResponse as? HTTPURLResponse)?.statusCode ?? 0
            if !(200..<300).contains(status) {
                let duplicate = String(data: uploadBody, encoding: .utf8)?.localizedCaseInsensitiveContains("already exists") == true
                    || String(data: uploadBody, encoding: .utf8)?.localizedCaseInsensitiveContains("duplicate") == true
                guard (status == 400 || status == 409), duplicate else { throw Self.mediaHTTPError(status: status, data: uploadBody) }
            }
            // The same frozen bearer spans upload and registration. A duplicate path is never
            // overwritten; the inspector compares actual bytes against this attempt's digest.
            var inspect = URLRequest(url: config.supabaseURL.appendingPathComponent("functions/v1/prepare-media"))
            inspect.httpMethod = "POST"
            snapshot.headers.forEach { inspect.setValue($0.value, forHTTPHeaderField: $0.key) }
            inspect.setValue("application/json", forHTTPHeaderField: "Content-Type")
            inspect.httpBody = try JSONSerialization.data(withJSONObject: ["uploadAttemptID": uploadAttemptID.uuidString.lowercased(), "purpose": purpose.rawValue, "sha256": digest])
            let (body, response) = try await send(inspect)
            let resultStatus = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(resultStatus) else { throw Self.mediaHTTPError(status: resultStatus, data: body) }
            return try RoamJSON.decoder.decode(StagedMedia.self, from: body)
        } catch { throw Self.map(error) }
    }

    func discardStaged(mediaID: UUID) async throws {
        try await rpcVoid("discard_staged_media", ["p_media_id": RPC.uuid(mediaID)])
    }

    func imageData(path: String) async throws -> Data {
        guard let storage = StoragePath(path) else { throw RoamError.notFound }
        let snapshot = try await requestSnapshot()
        guard snapshot.userID != nil else { throw RoamError.notSignedIn }
        var request = URLRequest(url: config.supabaseURL.appendingPathComponent("storage/v1/object/authenticated/\(storage.bucket)/\(storage.object)"))
        snapshot.headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        do {
            let (body, response) = try await send(request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(status) else { throw Self.mediaHTTPError(status: status, data: body) }
            return body
        } catch { throw Self.map(error) }
    }

    private static func mediaHTTPError(status: Int, data: Data) -> RoamError {
        let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        let message = object?["message"] as? String ?? object?["error"] as? String ?? ""
        if message.hasPrefix("roam:") { return mapDatabaseMessage(message, code: object?["code"] as? String) }
        if status == 401 { return .sessionExpired }
        if status == 403 { return .forbidden }
        if status == 404 { return .notFound }
        if status == 413 { return .validation("Photos must be 3 MB or smaller.") }
        if status == 409 { return .conflict("This upload attempt already contains a different photo.") }
        if status == 400 { return .validation(message.isEmpty ? "This photo could not be inspected." : message) }
        return .server("Photo storage is unavailable right now.")
    }
}
