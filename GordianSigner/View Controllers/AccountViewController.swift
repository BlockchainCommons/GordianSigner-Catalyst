//
//  AccountMapsViewController.swift
//  GordianSigner
//
//  Created by Peter on 11/16/20.
//  Copyright © 2020 Blockchain Commons. All rights reserved.
//

import UIKit
import LibWally

class AccountMapsViewController: UIViewController, UITableViewDelegate, UITableViewDataSource {
    
    var addButton = UIBarButtonItem()
    var editButton = UIBarButtonItem()
    var accounts = [[String:Any]]()
    let descriptorParser = DescriptorParser()
    var mapToExport = [String:Any]()
    var addressesAm:AccountStruct!
    
    @IBOutlet weak var accountMapTable: UITableView!
    
    override func viewDidLoad() {
        super.viewDidLoad()

        // Do any additional setup after loading the view.
        addButton.tintColor = .systemTeal
        editButton.tintColor = .systemTeal
        addButton = UIBarButtonItem.init(barButtonSystemItem: .add, target: self, action: #selector(add))
        editButton = UIBarButtonItem.init(barButtonSystemItem: .edit, target: self, action: #selector(editAccounts))
        self.navigationItem.setRightBarButtonItems([addButton, editButton], animated: true)
        
        if !FirstTime.firstTimeHere() {
            showAlert(self, "Fatal error", "We were unable to set and save an encryption key to your secure enclave, the app will not function without this key.")
        }
    }
    
    override func viewDidAppear(_ animated: Bool) {
        if UserDefaults.standard.object(forKey: "acceptDisclaimer") == nil {
            DispatchQueue.main.async {
                self.performSegue(withIdentifier: "segueToDisclaimer", sender: self)
            }
        } else {
            load()
            if UserDefaults.standard.object(forKey: "seenAccountInfo") == nil {
                showInfo()
                UserDefaults.standard.set(true, forKey: "seenAccountInfo")
            }
        }
    }
    
    @IBAction func infoAction(_ sender: Any) {
        showInfo()
    }
    
    private func load() {
        accounts.removeAll()
        
        CoreDataService.retrieveEntity(entityName: .account) { [weak self] (accounts, errorDescription) in
            guard let self = self else { return }
            
            guard let accounts = accounts, accounts.count > 0 else { return }
            
            for account in accounts {
                let str = AccountStruct(dictionary: account)
                self.accounts.append(["account": str])
            }
            
            self.loadCosigners()
        }
    }
    
    private func loadCosigners() {
        CoreDataService.retrieveEntity(entityName: .cosigner) { [weak self] (cosigners, errorDescription) in
            guard let self = self else { return }
            
            guard let cosigners = cosigners, cosigners.count > 0 else {
                
                for (i, account) in self.accounts.enumerated() {
                    let accountStruct = account["account"] as! AccountStruct
                    self.accounts[i]["canSign"] = false
                    
                    if !accountStruct.descriptor.contains("keyset") {
                        self.accounts[i]["lifeHash"] = LifeHash.image(accountStruct.descriptor)
                    }
                                        
                    if i + 1 == self.accounts.count {
                        DispatchQueue.main.async {
                            self.accountMapTable.reloadData()
                        }
                    }
                }
                
                return
            }
            
            for (i, account) in self.accounts.enumerated() {
                let accountStruct = account["account"] as! AccountStruct
                self.accounts[i]["canSign"] = false
                
                if !accountStruct.descriptor.contains("keyset") {
                    self.accounts[i]["lifeHash"] = LifeHash.image(accountStruct.descriptor)
                }
                
                var participants = ""
                for (k, cosigner) in cosigners.enumerated() {
                    let cosignerStruct = CosignerStruct(dictionary: cosigner)
                    
                    if let desc = cosignerStruct.bip48SegwitAccount {
                        
                        if accountStruct.descriptor.contains(desc) {
                            
                            let participant = cosignerStruct.label
                            
                            participants += participant + "\n"
                        }
                    }
                    
                    if k + 1 == cosigners.count {
                        self.accounts[i]["participants"] = participants
                    }
                }
                
                if i + 1 == self.accounts.count {
                    DispatchQueue.main.async {
                        self.accountMapTable.reloadData()
                    }
                }
            }
        }
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return 1
    }
    
    func numberOfSections(in tableView: UITableView) -> Int {
        if accounts.count > 0 {
            return accounts.count
        } else {
            return 1
        }
    }
    
    func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCell.EditingStyle, forRowAt indexPath: IndexPath) {
        if editingStyle == .delete {
            let account = accounts[indexPath.section]["account"] as! AccountStruct
            delete(account.id, indexPath.section)
        }
    }
    
    private func accountCell(_ indexPath: IndexPath) -> UITableViewCell {
        let cell = accountMapTable.dequeueReusableCell(withIdentifier: "accountCell", for: indexPath)
        cell.selectionStyle = .none
        cell.layer.cornerRadius = 8
        cell.layer.borderColor = UIColor.darkGray.cgColor
        cell.layer.borderWidth = 0.5
        
        let account = accounts[indexPath.section]["account"] as! AccountStruct
        let descriptor = account.descriptor
        let descriptorStruct = descriptorParser.descriptor(descriptor)
        
        let policy = cell.viewWithTag(2) as! UILabel
        policy.text = descriptorStruct.mOfNType
        
        let script = cell.viewWithTag(3) as! UILabel
        script.text = descriptorStruct.format
        
        let participantsLabel = cell.viewWithTag(4) as! UILabel
        if let participants = accounts[indexPath.section]["participants"] as? String {
            participantsLabel.text = participants
        } else {
            participantsLabel.text = ""
        }
        
        
        let isCompleteImage = cell.viewWithTag(5) as! UIImageView
        let completeLabel = cell.viewWithTag(12) as! UILabel
        let addButton = cell.viewWithTag(14) as! UIButton
        addButton.addTarget(self, action: #selector(addCosigner(_:)), for: .touchUpInside)
        addButton.restorationIdentifier = "\(indexPath.section)"
        
        let addressesButton = cell.viewWithTag(15) as! UIButton
        addressesButton.addTarget(self, action: #selector(seeAddresses(_:)), for: .touchUpInside)
        addressesButton.restorationIdentifier = "\(indexPath.section)"
        
        let editButton = cell.viewWithTag(9) as! UIButton
        editButton.addTarget(self, action: #selector(editLabel(_:)), for: .touchUpInside)
        editButton.restorationIdentifier = "\(indexPath.section)"
        
        let exportButton = cell.viewWithTag(10) as! UIButton
        exportButton.clipsToBounds = true
        exportButton.layer.cornerRadius = 8
        exportButton.restorationIdentifier = "\(indexPath.section)"
        exportButton.addTarget(self, action: #selector(exportQr(_:)), for: .touchUpInside)
        
        if account.descriptor.contains("keyset") {
            isCompleteImage.alpha = 1
            isCompleteImage.image = UIImage(systemName: "circle.lefthalf.fill")
            isCompleteImage.tintColor = .systemYellow
            completeLabel.text = "Account incomplete!"
            addButton.alpha = 1
            addressesButton.alpha = 0
            editButton.alpha = 0
            exportButton.alpha = 0
        } else {
            editButton.alpha = 1
            exportButton.alpha = 1
            isCompleteImage.alpha = 0
            isCompleteImage.tintColor = .systemGreen
            completeLabel.text = ""
            addButton.alpha = 0
            addressesButton.alpha = 1
        }
        
        let date = cell.viewWithTag(11) as! UILabel
        date.text = account.dateAdded.formatted()
        
        let lifehash = cell.viewWithTag(13) as! LifehashSeedView
        lifehash.background.backgroundColor = cell.backgroundColor
        lifehash.backgroundColor = cell.backgroundColor
        
        if let image = accounts[indexPath.section]["lifeHash"] as? UIImage {
            lifehash.lifehashImage.image = image
            lifehash.iconImage.image = UIImage(systemName: "person.2.square.stack")
            lifehash.iconLabel.text = account.label
            lifehash.iconImage.alpha = 1
            lifehash.iconLabel.alpha = 1
        } else {
            lifehash.lifehashImage.image = UIImage(systemName: "rectangle.badge.xmark")
            lifehash.lifehashImage.tintColor = .darkGray
            lifehash.iconImage.alpha = 0
            lifehash.iconLabel.alpha = 0
        }
        
        return cell
    }
    
    private func defaultCell(_ indexPath: IndexPath) -> UITableViewCell {
        let cell = accountMapTable.dequeueReusableCell(withIdentifier: "accountDefaultCell", for: indexPath)
        let button = cell.viewWithTag(1) as! UIButton
        button.addTarget(self, action: #selector(add), for: .touchUpInside)
        return cell
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        if accounts.count > 0 {
            return accountCell(indexPath)
        } else {
            return defaultCell(indexPath)
        }
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        if accounts.count > 0 {
            
            var height = 211
            let account = accounts[indexPath.section]["account"] as! AccountStruct
            let descParser = DescriptorParser()
            let descStruct = descParser.descriptor(account.descriptor)
            let hack = descStruct.mOfNType.replacingOccurrences(of: " of ", with: "*")
            let arr = hack.split(separator: "*")
            if arr.count > 0 {
                if let numberOfCosigners = Int("\(arr[1])") {
                    height += (numberOfCosigners * 10)
//                    switch numberOfCosigners {
//                    case _ where numberOfCosigners == 3:
//                        height = 257
//                    case _ where numberOfCosigners == 4:
//                        height = 277
//                    case _ where numberOfCosigners == 5:
//                        height = 287
//                    case _ where numberOfCosigners == 6:
//                        height = 297
//                    case _ where numberOfCosigners == 7:
//                        height = 307
//                    case _ where numberOfCosigners == 8:
//                        height = 317
//                    case _ where numberOfCosigners == 9:
//                        height = 327
//                    case _ where numberOfCosigners == 10:
//                        height = 337
//                    case _ where numberOfCosigners == 11:
//                        height = 347
//                    case _ where numberOfCosigners == 12:
//                        height = 357
//                    case _ where numberOfCosigners == 13:
//                        height = 367
//                    case _ where numberOfCosigners == 14:
//                        height = 377
//                    case _ where numberOfCosigners == 15:
//                        height = 387
//                    default:
//                        break
//                    }
                }
            }
            return CGFloat(height)
        } else {
            return 44
        }
    }
    
    @objc func seeAddresses(_ sender: UIButton) {
        guard let sectionString = sender.restorationIdentifier, let int = Int(sectionString) else { return }
        
        let am = accounts[int]["account"] as! AccountStruct
        
        DispatchQueue.main.async {
            self.addressesAm = am
            self.performSegue(withIdentifier: "segueToAddresses", sender: self)
        }
    }
    
    @objc func addCosigner(_ sender: UIButton) {
        guard let sectionString = sender.restorationIdentifier, let int = Int(sectionString) else { return }
        
        let am = accounts[int]["account"] as! AccountStruct
        var vettedCosigners = [CosignerStruct]()
        
        CoreDataService.retrieveEntity(entityName: .cosigner) { (cosigners, errorDescription) in
            guard let cosigners = cosigners, cosigners.count > 0 else {
                showAlert(self, "", "No cosigners added yet, add a cosigner first.")
                return
            }
            
            for (i, cosigner) in cosigners.enumerated() {
                let cosignerStruct = CosignerStruct(dictionary: cosigner)
                if !am.descriptor.contains(cosignerStruct.bip48SegwitAccount!) {
                    vettedCosigners.append(cosignerStruct)
                }
                
                if i + 1 == cosigners.count {
                    
                    if vettedCosigners.count > 0 {
                        DispatchQueue.main.async { [weak self] in
                            guard let self = self else { return }
                            
                            var alertStyle = UIAlertController.Style.actionSheet
                            if (UIDevice.current.userInterfaceIdiom == .pad) {
                              alertStyle = UIAlertController.Style.alert
                            }
                            
                            let alert = UIAlertController(title: "Which Cosigner?", message: "Select the cosigner to be added.", preferredStyle: alertStyle)
                            
                            for vettedCosigner in vettedCosigners {
                                alert.addAction(UIAlertAction(title: vettedCosigner.label, style: .default, handler: { action in
                                    self.updateAccountMap(am, vettedCosigner, int)
                                }))
                            }
                                            
                            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: { action in }))
                            alert.popoverPresentationController?.sourceView = self.view
                            self.present(alert, animated: true, completion: nil)
                        }
                    } else {
                        showAlert(self, "", "You can not add duplicate Cosigners to an account, add more Cosigners first.")
                    }
                    
                }
            }
        }
    }
    
    private func updateAccountMap(_ account: AccountStruct, _ cosigner: CosignerStruct, _ section: Int) {
        var desc = account.descriptor
        let descriptorParser = DescriptorParser()
        let descStruct = descriptorParser.descriptor(desc)
        var mofn = descStruct.mOfNType
        mofn = mofn.replacingOccurrences(of: " of ", with: "*")
        let arr = mofn.split(separator: "*")
        guard let n = Int(arr[1]) else { return }
        
        for i in 0...n - 1 {
            if desc.contains("<keyset #\(i + 1)>") {
                desc = desc.replacingOccurrences(of: "<keyset #\(i + 1)>", with: cosigner.bip48SegwitAccount!)
                break
            }
        }
        
        guard var dict = try? JSONSerialization.jsonObject(with: account.map, options: []) as? [String:Any] else { return }
        dict["descriptor"] = desc
        
        let updatedMap = (dict.json() ?? "").utf8
        
        CoreDataService.updateEntity(id: account.id, keyToUpdate: "descriptor", newValue: desc, entityName: .account) { (success, errorDesc) in
            guard success else {
                showAlert(self, "Descriptor updating failed...", "Please let us know about this bug.")
                return
            }
            
            CoreDataService.updateEntity(id: account.id, keyToUpdate: "map", newValue: updatedMap, entityName: .account) { (success, errorDesc) in
                guard success else {
                    showAlert(self, "Account map updating failed...", "Please let us know about this bug.")
                    return
                }
                
                CoreDataService.updateEntity(id: cosigner.id, keyToUpdate: "sharedWith", newValue: account.id, entityName: .cosigner) { (success, errorDescription) in
                    guard success else {
                        showAlert(self, "sharedWith updating failed...", "Please let us know about this bug.")
                        return
                    }
                    
                    CoreDataService.updateEntity(id: cosigner.id, keyToUpdate: "dateShared", newValue: Date(), entityName: .cosigner) { (success, errorDescription) in
                        guard success else {
                            showAlert(self, "dateShared updating failed...", "Please let us know about this bug.")
                            return
                        }
                        
                        DispatchQueue.main.async {
                            NotificationCenter.default.post(name: .cosignerAdded, object: nil, userInfo: nil)
                        }
                        
                        showAlert(self, "", "Account updated ✓")
                        
                        self.load()
                    }
                }
            }
        }
    }
    
    @objc func editLabel(_ sender: UIButton) {
        guard let sectionString = sender.restorationIdentifier, let int = Int(sectionString) else { return }
        
        let am = accounts[int]["account"] as! AccountStruct
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            let title = "Edit Account Map label"
            let message = ""
            let style = UIAlertController.Style.alert
            let alert = UIAlertController(title: title, message: message, preferredStyle: style)
            
            let save = UIAlertAction(title: "Save", style: .default) { [weak self] (alertAction) in
                guard let self = self else { return }
                
                let textField1 = (alert.textFields![0] as UITextField).text
                
                guard let updatedLabel = textField1, updatedLabel != "" else { return }
                
                self.updateLabel(am.id, updatedLabel)
            }
            
            alert.addTextField { (textField) in
                textField.text = am.label
                textField.isSecureTextEntry = false
                textField.keyboardAppearance = .dark
            }
            
            alert.addAction(save)
            
            let cancel = UIAlertAction(title: "Cancel", style: .default) { (alertAction) in }
            alert.addAction(cancel)
            
            self.present(alert, animated:true, completion: nil)
        }
    }
    
    private func updateLabel(_ id: UUID, _ label: String) {
        CoreDataService.updateEntity(id: id, keyToUpdate: "label", newValue: label, entityName: .account) { (success, errorDescription) in
            guard success else { showAlert(self, "Label not saved!", "There was an error updating your label, please let us know about it: \(errorDescription ?? "unknown")"); return }
            
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .cosignerAdded, object: nil, userInfo: nil)
            }
            
            self.load()
        }
    }
    
    @objc func exportQr(_ sender: UIButton) {
        guard let sectionString = sender.restorationIdentifier, let int = Int(sectionString) else { return }
        
        let accountMapData = (accounts[int]["account"] as! AccountStruct).map
        
        guard let dict = try? JSONSerialization.jsonObject(with: accountMapData, options: []) as? [String:Any] else { return }
        
        mapToExport = dict
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            self.performSegue(withIdentifier: "segueToExportAccountMap", sender: self)
        }
    }
    
    @objc func add() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            var alertStyle = UIAlertController.Style.actionSheet
            if (UIDevice.current.userInterfaceIdiom == .pad) {
              alertStyle = UIAlertController.Style.alert
            }
            
            let alert = UIAlertController(title: "Add Account", message: "You may either create a new account or import one.", preferredStyle: alertStyle)
            
            alert.addAction(UIAlertAction(title: "Import", style: .default, handler: { action in
                DispatchQueue.main.async { [weak self] in
                    self?.performSegue(withIdentifier: "segueToAddAccountMap", sender: self)
                }
            }))
            
            alert.addAction(UIAlertAction(title: "Create", style: .default, handler: { action in
                DispatchQueue.main.async { [weak self] in
                    self?.performSegue(withIdentifier: "createAccountMap", sender: self)
                }
            }))
            
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: { action in }))
            alert.popoverPresentationController?.sourceView = self.view
            self.present(alert, animated: true, completion: nil)
        }
    }
    
    @objc func editAccounts() {
        if accounts.count > 0 {
            accountMapTable.setEditing(!accountMapTable.isEditing, animated: true)
        } else {
            accountMapTable.setEditing(false, animated: true)
        }
        
        if accountMapTable.isEditing {
            editButton = UIBarButtonItem(title: "Done", style: .plain, target: self, action: #selector(editAccounts))
        } else {
            editButton = UIBarButtonItem(title: "Edit", style: .plain, target: self, action: #selector(editAccounts))
        }
        
        self.navigationItem.setRightBarButtonItems([addButton, editButton], animated: true)
    }
    
    @objc func delete(_ id: UUID, _ section: Int) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            var alertStyle = UIAlertController.Style.actionSheet
            if (UIDevice.current.userInterfaceIdiom == .pad) {
              alertStyle = UIAlertController.Style.alert
            }
            
            let alert = UIAlertController(title: "Delete Account?", message: "", preferredStyle: alertStyle)
            
            alert.addAction(UIAlertAction(title: "Delete", style: .destructive, handler: { action in
                self.deleteAccountMapNow(id, section)
            }))
            
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: { action in }))
            alert.popoverPresentationController?.sourceView = self.view
            self.present(alert, animated: true, completion: nil)
        }
    }
    
    private func deleteAccountMapNow(_ id: UUID, _ section: Int) {
        CoreDataService.deleteEntity(id: id, entityName: .account) { (success, errorDescription) in
            guard success else {
                showAlert(self, "Error deleting Account", "")
                return
            }
            
            DispatchQueue.main.async { [weak self] in
                self?.accounts.remove(at: section)
                if self?.accounts.count == 0 {
                    self?.editAccounts()
                    self?.accountMapTable.reloadData()
                } else {
                    self?.accountMapTable.deleteSections(IndexSet.init(arrayLiteral: section), with: .fade)
                }
            }
            
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .cosignerAdded, object: nil, userInfo: nil)
            }
        }
    }
    
    private func parseAccountMap(_ accountMap: String) {
        guard let dict = try? JSONSerialization.jsonObject(with: accountMap.utf8, options: []) as? [String:Any] else { return }
        
        guard var descriptor = dict["descriptor"] as? String, !descriptor.contains("keyset") else { return }
        
        let accountMapId = UUID()
        
        let descriptorParser = DescriptorParser()
        var descStruct = descriptorParser.descriptor(descriptor)
    
        descriptor = descriptor.replacingOccurrences(of: "'", with: "h")
        let arr = descriptor.split(separator: "#")
        descriptor = "\(arr[0])"
        descStruct = descriptorParser.descriptor(descriptor)
        
        // Add range
        if !descriptor.contains("/0/*") {
            for key in descStruct.multiSigKeys {
                if !key.contains("/0/*") {
                    descriptor = descriptor.replacingOccurrences(of: key, with: key + "/0/*")
                }
            }
        }
        
        descStruct = descriptorParser.descriptor(descriptor)
        
        // If the descriptor is multisig, we sort the keys lexicographically
        if descriptor.contains(",") {
            var dictArray = [[String:String]]()
            
            for keyWithPath in descStruct.keysWithPath {
                guard keyWithPath.contains("/48h/\(Keys.coinType)h/0h/2h") || keyWithPath.contains("/48'/\(Keys.coinType)'/0'/2'") else {
                    showAlert(self, "Unsupported key origin", "Gordian Cosigner currently only supports the m/48'/\(Keys.coinType)'/0'/2' origin.")
                    return
                }
                let arr = keyWithPath.split(separator: "]")
                if arr.count > 1 {
                    var xpubString = "\(arr[1].replacingOccurrences(of: "))", with: ""))"
                    xpubString = xpubString.replacingOccurrences(of: "/0/*", with: "")
                    guard let xpub = try? HDKey(base58: xpubString) else {
                        showAlert(self, "Key invalid", "Gordian Cosigner does not yet support slip0132 keys. Please ensure your xpub is valid then try again.")
                        return
                    }
                    
                    let dict = ["path":"\(arr[0])]", "key": xpub.description]
                    dictArray.append(dict)
                }
            }
            
            dictArray.sort(by: {($0["key"]!) < $1["key"]!})
            
            var sortedKeys = ""
            
            for (i, sortedItem) in dictArray.enumerated() {
                let path = sortedItem["path"]!
                let key = sortedItem["key"]!
                let fullKey = path + key
                
                let hack = "wsh(\(fullKey)/0/*)"
                let dp = DescriptorParser()
                let ds = dp.descriptor(hack)
                let account = fullKey.replacingOccurrences(of: "/0/*", with: "")
                
                var cosigner = [String:Any]()
                cosigner["id"] = UUID()
                cosigner["label"] = "Cosigner #\(i + 1)"
                cosigner["bip48SegwitAccount"] = account
                cosigner["dateAdded"] = Date()
                cosigner["fingerprint"] = ds.fingerprint
                cosigner["sharedWith"] = accountMapId
                cosigner["dateShared"] = Date()
                
                // First fetch all existing cosigners to ensure we do not save duplicates
                CoreDataService.retrieveEntity(entityName: .cosigner) { (cosigners, errorDescription) in
                    var alreadyExists = false
                    
                    if let cosigners = cosigners, cosigners.count > 0 {
                        for (i, cosigner) in cosigners.enumerated() {
                            let cosignerStruct = CosignerStruct(dictionary: cosigner)
                            
                            if cosignerStruct.bip48SegwitAccount != nil {
                                if cosignerStruct.bip48SegwitAccount! == account {
                                    alreadyExists = true
                                }
                            }
                            
                            if i + 1 == cosigners.count {
                                if !alreadyExists {
                                    CoreDataService.saveEntity(dict: cosigner, entityName: .cosigner) { (_, _) in }
                                }
                            }
                        }
                    } else {
                        CoreDataService.saveEntity(dict: cosigner, entityName: .cosigner) { (_, _) in }
                    }
                }
                
                sortedKeys += fullKey
                
                if i + 1 < dictArray.count {
                    sortedKeys += ","
                }
            }
            
            let arr2 = descriptor.split(separator: ",")
            descriptor = "\(arr2[0])," + sortedKeys + "))"
        }
        
        var map = [String:Any]()
        map["blockheight"] = Int64(dict["blockheight"] as? Int ?? 0)
        map["accountMap"] = accountMap.utf8
        map["label"] = dict["label"] as? String ?? "Account map"
        map["id"] = accountMapId
        map["dateAdded"] = Date()
        map["complete"] = descStruct.complete
        map["lifehash"] = LifeHash.hash(descriptor.utf8)
        map["descriptor"] = descriptor.condenseWhitespace()
        
        CoreDataService.saveEntity(dict: map, entityName: .account) { [weak self] (success, errorDescription) in
            guard let self = self, success else { return }
            
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .cosignerAdded, object: nil, userInfo: nil)
            }
            
            self.load()
        }
    }
    
    private func showInfo() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            self.performSegue(withIdentifier: "segueToAccountsInfo", sender: self)
        }
    }
    
    // MARK: - Navigation

    // In a storyboard-based application, you will often want to do a little preparation before navigation
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        // Get the new view controller using segue.destination.
        // Pass the selected object to the new view controller.
        if segue.identifier == "segueToAddAccountMap" {
            if let vc = segue.destination as? QRScannerViewController {
                vc.doneBlock = { [weak self] accountMap in
                    guard let self = self, let accountMap = accountMap else { return }
                                        
                    self.parseAccountMap(accountMap)
                }
            }
        }
        
        if segue.identifier == "segueToExportAccountMap" {
            if let vc = segue.destination as? QRDisplayerViewController {
                vc.header = "Account Map"
                vc.descriptionText = mapToExport.json() ?? ""
                vc.isPsbt = false
                vc.text = mapToExport.json() ?? ""
            }
        }
        
        if segue.identifier == "segueToAddresses" {
            if let vc = segue.destination as? AddressesViewController {
                vc.account = self.addressesAm
            }
        }
        
        if segue.identifier == "createAccountMap" {
            if let vc = segue.destination as? CreateAccountMapViewController {
                vc.doneBlock = { [weak self] accountMap in
                    guard let self = self, let accountMap = accountMap else { return }
                                        
                    self.parseAccountMap(accountMap)
                }
            }
        }
        
        if segue.identifier == "segueToAccountsInfo" {
            if let vc = segue.destination as? InfoViewController {
                vc.isAccount = true
            }
        }
    }
    
    // MARK: - Never used the app before
    
    private func promptToCreate() {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            
            let alert = UIAlertController(title: "Create defaults?", message: "Would you like the app to create a default cosigner for this device?", preferredStyle: .alert)
            
            alert.addAction(UIAlertAction(title: "Create", style: .default, handler: { action in
                self.createSigner()
            }))
                            
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel, handler: { action in }))
            alert.popoverPresentationController?.sourceView = self.view
            self.present(alert, animated: true, completion: nil)
        }
    }
    
    private func createSigner() {
        guard let words = Keys.seed(),
            let entropy = Keys.entropy(words),
            let encryptedData = Encryption.encrypt(entropy),
            let masterKey = Keys.masterXprv(words, ""),
            let fingerprint = Keys.fingerprint(masterKey),
            let lifeHash = LifeHash.hash(entropy),
            let cosigner = Keys.bip48SegwitAccount(masterKey) else {
                showAlert(self, "Error ⚠️", "Something went wrong, private keys not saved!")
                return
        }
        
        var dict = [String:Any]()
        dict["id"] = UUID()
        dict["label"] = UIDevice.current.name
        dict["dateAdded"] = Date()
        dict["lifeHash"] = lifeHash
        dict["fingerprint"] = fingerprint
        dict["entropy"] = encryptedData
        dict["cosigner"] = cosigner
        
//        CoreDataService.saveEntity(dict: dict, entityName: .signer) { [weak self] (success, errorDescription) in
//            guard let self = self else { return }
//
//            guard success else {
//                showAlert(self, "Error ⚠️", "Failed saving to Core Data!")
//                return
//            }
//
//            self.saveKeysets(masterKey, UIDevice.current.name, fingerprint)
//        }
    }
    
    private func saveCosigners(_ masterKey: String, _ label: String, _ xfp: String) {
        let idToShare = UUID()
        var cosigner = [String:Any]()
        cosigner["id"] = UUID()
        cosigner["label"] = label
        cosigner["fingerprint"] = xfp
        
        guard let bip48SegwitAccount = Keys.bip48SegwitAccount(masterKey) else {
            showAlert(self, "Key derivation failed", "")
            return
        }
        
        cosigner["bip48SegwitAccount"] = bip48SegwitAccount
        cosigner["dateAdded"] = Date()
        cosigner["dateShared"] = Date()
        cosigner["sharedWith"] = idToShare
        
        CoreDataService.saveEntity(dict: cosigner, entityName: .cosigner) { [weak self] (success, errorDescription) in
            guard let self = self else { return }

            guard success else {
                showAlert(self, "Failed to save cosigner", errorDescription ?? "unknown error")
                return
            }
            
            DispatchQueue.main.async {
                NotificationCenter.default.post(name: .cosignerAdded, object: nil, userInfo: nil)
            }
            
            self.createPolicyMap(bip48SegwitAccount, idToShare)
        }
    }
    
    private func createPolicyMap(_ cosigner: String, _ id: UUID) {
        let desc = "wsh(sortedmulti(2,\(cosigner),<keyset #2>,<keyset #3>))"
        
        let accountMap = ["descriptor":desc, "blockheight":0, "label":"Incomplete Account"] as [String : Any]
        let json = accountMap.json() ?? ""
        
        var map = [String:Any]()
        map["blockheight"] = Int64(0)
        map["accountMap"] = json.utf8
        map["label"] = "Incomplete Account"
        map["id"] = id
        map["dateAdded"] = Date()
        map["complete"] = false
        map["descriptor"] = desc
        
        CoreDataService.saveEntity(dict: map, entityName: .account) { [weak self] (success, errorDescription) in
            guard let self = self, success else { return }
            
            UserDefaults.standard.set(true, forKey: "createDefaults")
            self.load()
        }
    }

}