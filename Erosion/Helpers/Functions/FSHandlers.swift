//
//  FSHandlers.swift
//  Erosion
//
//  Created by lunginspector on 8/19/26.
//

import Foundation
import UIKit

let fsHandlers = FSHandlers()

class FSHandlers {
    func getDirPaths(_ path: String, maxInode: Int64 = 10000000) -> [String] {
        var array = [""]
        path.withCString { path in
            guard let res = bad_query_list(UnsafeMutablePointer(mutating: path), maxInode) else {
                return
            }
            defer { free(res) }
            
            let string = String(cString: res)
            array = string.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        }
        return array
    }
    
    /// Runs a read-only directory operation while a BadQuery sandbox extension
    /// for that exact directory is active. Unlike grantAccess(atPath:), this does
    /// not require the directory to be writable (app bundle roots are read-only).
    func withReadAccessToDirectory<T>(atPath path: String, perform: () throws -> T) throws -> T {
        guard path.hasPrefix("/"), !path.isEmpty else {
            throw NSError(domain: "Erosion.FSHandlers", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid directory path."])
        }

        var pathCString = path.utf8CString.map { Int8($0) }
        let handle = bad_query(&pathCString, false, nil, false, nil)
        guard handle >= 0 else {
            throw NSError(
                domain: "Erosion.FSHandlers.BadQuery",
                code: Int(handle),
                userInfo: [NSLocalizedDescriptionKey: "BadQuery could not grant read access to \(path) (\(handle))."]
            )
        }
        defer { bad_query_release(handle) }
        return try perform()
    }

    func getContainerPath(at containerURL: URL = FSURL.appContainers, forMatch match: String, hashOnly: Bool = false) -> String {
        let containers = getDirPaths(containerURL.path)
        for path in containers {
            let url = URL(fileURLWithPath: path)
            if let appName = folderLabel(url: url) {
                if appName == match {
                    if hashOnly {
                        return url.lastPathComponent
                    }
                    return url.path
                }
            }
        }
        print("(fs) failed to get container for \(match)! containers: \(containerURL.path)")
        return ""
    }
    
    func openInFilesApp(_ fileURL: URL) {
        guard var components = URLComponents(url: fileURL, resolvingAgainstBaseURL: false) else { return }
        components.scheme = "shareddocuments"
        guard let filesAppURL = components.url else { return }
        UIApplication.shared.open(filesAppURL)
    }
}
