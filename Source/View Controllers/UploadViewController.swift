//
//  UploadViewController.swift
//  PPPC Utility
//
//  MIT License
//
//  Copyright (c) 2018 Jamf Software
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in all
//  copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//  SOFTWARE.
//

import Cocoa
import CoreGraphics

class UploadViewController: NSViewController {

    private static var uploadKVOContext = 0

    @objc dynamic var networkOperationsTitle: String! = nil
    @objc dynamic var mustSignForUpload: Bool = true {
        didSet {
            let containsNullRef = (identitiesPopUpAC.arrangedObjects as? [SigningIdentity])?.first?.reference == nil
            if mustSignForUpload && containsNullRef {
                identitiesPopUpAC.remove(atArrangedObjectIndex: 0)
            } else if !mustSignForUpload && !containsNullRef {
                let nullRef = SigningIdentity(name: "Profile signed by server", reference: nil)
                identitiesPopUpAC.insert(nullRef, atArrangedObjectIndex: 0)
            }
        }
    }

    @objc dynamic var credentialsAvailable = false
    @objc dynamic var credentialsVerified = false
    @objc dynamic var saveCredentials = true
    @objc dynamic var readyForUpload = false

    @objc dynamic var username: String?
    @objc dynamic var password: String?
    @objc dynamic var payloadName: String?
    @objc dynamic var payloadIdentifier = UUID().uuidString
    @objc dynamic var payloadDescription: String?

    @objc dynamic var site = false
    @objc dynamic var siteName: String?
    @objc dynamic var siteId: String?

    @IBOutlet weak var defaultsController: NSUserDefaultsController!

    @IBOutlet weak var jamfProServerLabel: NSTextField!
    @IBOutlet weak var usernameLabel: NSTextField!
    @IBOutlet weak var passwordLabel: NSSecureTextField!
    @IBOutlet weak var organizationLabel: NSTextField!
    @IBOutlet weak var payloadNameLabel: NSTextField!
    @IBOutlet weak var payloadIdentifierLabel: NSTextField!
    @IBOutlet weak var payloadDescriptionLabel: NSTextField!
    @IBOutlet weak var identitiesPopUp: NSPopUpButton!
    @IBOutlet var identitiesPopUpAC: NSArrayController!
    @IBOutlet weak var uploadButton: NSButton!
    @IBOutlet weak var checkConnectionButton: NSButton!
    @IBOutlet weak var siteIdLabel: NSTextField!
    @IBOutlet weak var siteNameLabel: NSTextField!

    @IBOutlet weak var gridView: NSGridView!

    @IBAction func uploadPressed(_ sender: NSButton) {
        print("Uploading profile: \(payloadName ?? "?")")
        self.networkOperationsTitle = "Uploading \(payloadName ?? "profile")"

        guard let username = username, let password = password else {
            print("Username or password not set")
            Alert().display(header: "Attention:", message: "Username or password not set")
            return
        }
        guard username.firstIndex(of: ":") == nil else {
            print("Username cannot contain a colon")
            Alert().display(header: "Attention:", message: "Username cannot contain a colon")
            return
        }

        let model = Model.shared
        let profile = model.exportProfile(organization: organizationLabel.stringValue,
                                          identifier: payloadIdentifierLabel.stringValue,
                                          displayName: payloadNameLabel.stringValue,
                                          payloadDescription: payloadDescriptionLabel.stringValue)
        var identity: SecIdentity?
        if mustSignForUpload, let signingIdentity = identitiesPopUpAC.selectedObjects.first as? SigningIdentity, signingIdentity.reference != nil {
            print("Signing profile with \(signingIdentity.displayName)")
            identity = signingIdentity.reference
        }

        var siteIdAndName: (String, String)?
        if site {
            if let siteId = siteId, let siteName = siteName, siteId != "", siteName != "" {
                siteIdAndName = (siteId, siteName)
            }
        }

        let authManager = NetworkAuthManager(username: username, password: password)
        let networking = JamfProAPIClient(serverUrlString: jamfProServerLabel.stringValue, tokenManager: authManager)
        Task {
            let success: Bool
            do {
                let profileData = try profile.jamfProAPIData(signingIdentity: identity, site: siteIdAndName)

                _ = try await networking.upload(computerConfigProfile: profileData)

                success = true
            } catch {
                print("Error creating or upload profile: \(error)")
                success = false
            }

            DispatchQueue.main.async {
                self.handleUploadCompletion(success: success)
            }
        }
    }

    @IBAction func checkConnectionPressed(_ sender: NSButton) {
        guard let username = username, let password = password else {
            print("Username or password not set")
            Alert().display(header: "Attention:", message: "Username or password not set")
            DispatchQueue.main.async {
                self.handleCheckConnectionFailure(enforceSigning: nil)
            }
            return
        }
        guard username.firstIndex(of: ":") == nil else {
            print("Username cannot contain a colon")
            Alert().display(header: "Attention:", message: "Username cannot contain a colon")
            DispatchQueue.main.async {
                self.handleCheckConnectionFailure(enforceSigning: nil)
            }
            return
        }

        print("Checking connection")
        self.networkOperationsTitle = "Checking Jamf Pro server"

        let authManager = NetworkAuthManager(username: username, password: password)
        let networking = JamfProAPIClient(serverUrlString: jamfProServerLabel.stringValue, tokenManager: authManager)
        Task {
            do {
                let version = try await networking.getJamfProVersion()

                // Must sign if Jamf Pro is less than v10.7.1
                let mustSign = (version.semantic() < SemanticVersion(major: 10, minor: 7, patch: 1))

                let organizationName = try await networking.getOrganizationName()

                DispatchQueue.main.async {
                    self.handleCheckConnection(enforceSigning: mustSign,
                                               organization: organizationName)
                }
            } catch is AuthError {
                print("Invalid username/password")
                Alert().display(header: "Attention:", message: "Invalid username/password")
                DispatchQueue.main.async {
                    self.handleCheckConnectionFailure(enforceSigning: nil)
                }
            } catch {
                print("Jamf Pro server is unavailable")
                Alert().display(header: "Attention:", message: "Jamf Pro server is unavailable")
                DispatchQueue.main.async {
                    self.handleCheckConnectionFailure(enforceSigning: nil)
                }
            }
        }
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        checkConnectionButton.isEnabled = false
        organizationLabel.isEnabled = false
        payloadNameLabel.isEnabled = false
        payloadIdentifierLabel.isEnabled = false
        payloadDescriptionLabel.isEnabled = false

        do {
            let identities = try SecurityWrapper.loadSigningIdentities()
            identitiesPopUpAC.add(contentsOf: identities)
        } catch {
            identitiesPopUpAC.add(contentsOf: [])
            print("Error loading identities: \(error)")
        }

        mustSignForUpload = UserDefaults.standard.bool(forKey: "enforceSigning")

        loadCredentials()
        loadImportedTCCProfileInfo()
        updateSiteUI()
    }

    override func viewWillAppear() {
        super.viewWillAppear()
        defaultsController.addObserver(self, forKeyPath: "values.jamfProServer", options: [.new], context: &UploadViewController.uploadKVOContext)
        defaultsController.addObserver(self, forKeyPath: "values.organization", options: [.new], context: &UploadViewController.uploadKVOContext)
        addObserver(self, forKeyPath: "username", options: [.new], context: &UploadViewController.uploadKVOContext)
        addObserver(self, forKeyPath: "password", options: [.new], context: &UploadViewController.uploadKVOContext)
        addObserver(self, forKeyPath: "payloadName", options: [.new], context: &UploadViewController.uploadKVOContext)
        addObserver(self, forKeyPath: "payloadDescription", options: [.new], context: &UploadViewController.uploadKVOContext)
        addObserver(self, forKeyPath: "payloadIdentifier", options: [.new], context: &UploadViewController.uploadKVOContext)

        addObserver(self, forKeyPath: "site", options: [.new], context: &UploadViewController.uploadKVOContext)
        addObserver(self, forKeyPath: "siteId", options: [.new], context: &UploadViewController.uploadKVOContext)
        addObserver(self, forKeyPath: "siteName", options: [.new], context: &UploadViewController.uploadKVOContext)

        if organizationLabel.stringValue.isEmpty {
            organizationLabel.becomeFirstResponder()
        } else if credentialsAvailable {
            payloadNameLabel.becomeFirstResponder()
        } else {
            usernameLabel.becomeFirstResponder()
        }
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        defaultsController.removeObserver(self, forKeyPath: "values.jamfProServer", context: &UploadViewController.uploadKVOContext)
        defaultsController.removeObserver(self, forKeyPath: "values.organization", context: &UploadViewController.uploadKVOContext)
        removeObserver(self, forKeyPath: "username", context: &UploadViewController.uploadKVOContext)
        removeObserver(self, forKeyPath: "password", context: &UploadViewController.uploadKVOContext)
        removeObserver(self, forKeyPath: "payloadName", context: &UploadViewController.uploadKVOContext)
        removeObserver(self, forKeyPath: "payloadDescription", context: &UploadViewController.uploadKVOContext)
        removeObserver(self, forKeyPath: "payloadIdentifier", context: &UploadViewController.uploadKVOContext)

        removeObserver(self, forKeyPath: "site", context: &UploadViewController.uploadKVOContext)
        removeObserver(self, forKeyPath: "siteId", context: &UploadViewController.uploadKVOContext)
        removeObserver(self, forKeyPath: "siteName", context: &UploadViewController.uploadKVOContext)

        //  Save keychain
        syncronizeCredentials()
    }

    // swiftlint:disable:next block_based_kvo
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
        if context == &UploadViewController.uploadKVOContext {
            updateCredentialsAvailable()
            updateReadForUpload()
            updateSiteUI()
        } else {
            super.observeValue(forKeyPath: keyPath, of: object, change: change, context: context)
        }
    }

    func updateCredentialsAvailable() {
        if let username = username, !username.isEmpty,
           let password = password, !password.isEmpty,
           !jamfProServerLabel.stringValue.isEmpty {
            credentialsAvailable = true
        } else {
            credentialsAvailable = false
        }
    }

    func updateReadForUpload() {
        guard let payloadName = payloadName, !payloadName.isEmpty else {
            readyForUpload = false
            return
        }

        guard readyForUpload != (
            credentialsVerified
            && credentialsAvailable
            && !organizationLabel.stringValue.isEmpty
            && !payloadIdentifier.isEmpty
            && isSiteReadyToUpload())
            else { return }

        readyForUpload = !readyForUpload
    }

    func isSiteReadyToUpload() -> Bool {
        if site {
            if let siteId = siteId, let siteName = siteName, siteId != "", siteName != "" {
                return true
            } else {
                return false
            }
        } else {
            return true
        }
    }

    func updateSiteUI() {
        siteIdLabel.isHidden = !site
        siteNameLabel.isHidden = !site
    }

    func handleCheckConnectionFailure(enforceSigning: Bool?) {
        identitiesPopUp.isEnabled = enforceSigning ?? false
        networkOperationsTitle = nil
        credentialsVerified = false
        updateReadForUpload()
        passwordLabel.becomeFirstResponder()
    }

    func handleCheckConnection(enforceSigning: Bool, organization: String) {
        defaultsController.setValue(organization, forKeyPath: "values.organization")
        UserDefaults.standard.set(enforceSigning, forKey: "enforceSigning")
        networkOperationsTitle = nil
        mustSignForUpload = enforceSigning
        syncronizeCredentials()
        credentialsVerified = true
        payloadNameLabel.becomeFirstResponder()
        updateReadForUpload()
    }

    func handleUploadCompletion(success: Bool) {
        guard !success else {
            print("Uploaded successfully")
            self.dismiss(nil)
            return
        }

        print("Failed to upload")

        networkOperationsTitle = nil
        credentialsVerified = false
        passwordLabel.becomeFirstResponder()
        updateReadForUpload()
    }

    func loadCredentials() {
        if let server = UserDefaults.standard.string(forKey: "jamfProServer") {
            do {
                let possibleCredentials = try SecurityWrapper.loadCredentials(server: server)
                if let credentials = possibleCredentials {
                    username = credentials.username
                    password = credentials.password
                    credentialsAvailable = true
                    credentialsVerified = true
                    return
                }
            } catch {
                print("Error loading credentials: \(error)")
            }
        }

        username = nil
        password = nil
        credentialsAvailable = false
        credentialsVerified = false
    }

    func loadImportedTCCProfileInfo() {
        let model = Model.shared

        if let tccProfile = model.importedTCCProfile {
            organizationLabel.stringValue = tccProfile.organization
            payloadName = tccProfile.displayName
            payloadDescription = tccProfile.payloadDescription
            payloadIdentifier = tccProfile.identifier
        }
    }

    func syncronizeCredentials() {
        if saveCredentials {
            if let username = username, let password = password, credentialsAvailable {
                do {

                    try SecurityWrapper.saveCredentials(username: username,
                                                        password: password,
                                                        server: jamfProServerLabel.stringValue)
                } catch {
                    print("Failed to save credentials with error: \(error)")
                }
            }
        } else {
            guard let username = username else { return }
            try? SecurityWrapper.removeCredentials(server: jamfProServerLabel.stringValue, username: username)
        }
    }
}
