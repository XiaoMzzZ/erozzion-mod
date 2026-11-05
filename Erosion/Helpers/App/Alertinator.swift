//
//  Alertinator.swift
//  PartyUI
//
//  Created by lunginspector on 2/12/26.
//

import Foundation
import UIKit

@MainActor
public class Alertinator {
    public static let shared = Alertinator()
    
    var alertController: UIAlertController?
    
    public func alert(title: String, body: String, showCancel: Bool = true) {
        Task { @MainActor in
            alertController = UIAlertController(title: localized(title), message: localized(body), preferredStyle: .alert)
            if showCancel {
                alertController?.addAction(.init(title: localized("OK"), style: .cancel))
            }
            alertController?.view.tintColor = UIColor(named: "AccentColor")
            self.present(alertController!)
        }
    }
    
    public func alert(
        title: String,
        body: String,
        showCancel: Bool = true,
        actionLabel: String = "OK",
        actionStyle: UIAlertAction.Style = .default,
        action: @escaping () -> Void
    ) {
        Task { @MainActor in
            alertController = UIAlertController(title: localized(title), message: localized(body), preferredStyle: .alert)
            alertController?.addAction(.init(title: localized(actionLabel), style: actionStyle) { _ in
                action()
            })
            if showCancel {
                alertController?.addAction(.init(title: localized("Cancel"), style: .cancel))
            }
            alertController?.view.tintColor = UIColor(named: "AccentColor")
            self.present(alertController!)
        }
    }
    
    public func prompt(title: String, placeholder: String = "", text: String = "", showCancel: Bool = true, completion: @escaping (String?) async -> Void) {
        Task { @MainActor in
            alertController = UIAlertController(title: localized(title), message: nil, preferredStyle: .alert)
            alertController?.addTextField { field in
                if !placeholder.isEmpty {
                    // Deliberately NOT localized here: several call sites pass a live
                    // file name as the placeholder (e.g. rename), and running that
                    // through the strings table would rewrite the user's file name if
                    // it happened to collide with a UI key. Static placeholders are
                    // localized at their call sites instead.
                    field.placeholder = placeholder
                }
                if !text.isEmpty {
                    field.text = text
                }
            }
            if showCancel {
                alertController?.addAction(UIAlertAction(title: localized("Cancel"), style: .cancel) { _ in
                    Task {
                        await completion(nil)
                    }
                })
            }
            alertController?.addAction(UIAlertAction(title: localized("OK"), style: .default) { _ in
                let field = self.alertController?.textFields?.first
                Task {
                    await completion(field?.text)
                }
            })
            alertController?.view.tintColor = UIColor(named: "AccentColor")
            self.present(alertController!)
        }
    }
    
    @MainActor
    private func present(_ alert: UIAlertController) {
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first,
           var topController = window.rootViewController {
            
            while let presentedViewController = topController.presentedViewController {
                topController = presentedViewController
            }
            
            topController.present(alert, animated: true)
        }
    }
}
