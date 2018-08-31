import Flutter
import UIKit
import Contacts
import ContactsUI

@available(iOS 9.0, *)
public class SwiftContactsServicePlugin: NSObject, FlutterPlugin, CNContactPickerDelegate, CNContactViewControllerDelegate {

    let rootViewController:UIViewController
    
    var flutterResult:  FlutterResult?
    
    init(rootViewController:UIViewController){
        self.rootViewController = rootViewController
    }


    public static func register(with registrar: FlutterPluginRegistrar) {
        let channel = FlutterMethodChannel(name: "github.com/clovisnicolas/flutter_contacts", binaryMessenger: registrar.messenger())
        let rootViewController = UIApplication.shared.delegate?.window??.rootViewController;
        let instance = SwiftContactsServicePlugin(rootViewController: rootViewController!)
        registrar.addMethodCallDelegate(instance, channel: channel)
    }
    
    public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "pickContact":
            self.flutterResult = result
            let contactPicker = CNContactPickerViewController()
            contactPicker.delegate = self
            self.rootViewController.present(contactPicker, animated: true, completion: nil)
        case "getContacts":
            result(getContacts(query: (call.arguments as! String?)))
        case "exportContact":
            self.flutterResult = result
            let contact = dictionaryToContact(dictionary: call.arguments as! [String : Any])
            let toBeEditedContact = CNContactViewController(forNewContact: contact)
            toBeEditedContact.contactStore = CNContactStore()
            toBeEditedContact.delegate = self
            toBeEditedContact.allowsEditing = true
            toBeEditedContact.allowsActions = true
            let navigationController = UINavigationController(rootViewController: toBeEditedContact)
            self.rootViewController.present(navigationController, animated: true, completion: nil)
        case "addContact":
            self.flutterResult = result
            let contact = dictionaryToContact(dictionary: call.arguments as! [String : Any])
            if(addContact(contact: contact)){
                result(nil)
            }
            else{
                result(FlutterError(code: "", message: "Failed to add contact", details: nil))
            }
        case "deleteContact":
            if(deleteContact(dictionary: call.arguments as! [String : Any])){
                result(nil)
            }
            else{
                result(FlutterError(code: "", message: "Failed to delete contact, make sure it has a valid identifier", details: nil))
            }
        default:
            result(FlutterMethodNotImplemented)
        }
    }
    
    public func contactPicker(_ picker: CNContactPickerViewController,
                       didSelect contact: CNContact) {
        self.flutterResult?(contactToDictionary(contact: contact))
    }

    public func contactViewController(_ viewController: CNContactViewController,
                    didCompleteWith contact: CNContact?){
        self.flutterResult?(nil)
        viewController.dismiss(animated: true, completion: nil)
    }
    

    func getContacts(query : String?) -> [[String:Any]]{
        var contacts : [CNContact] = []
        //Create the store, keys & fetch request
        let store = CNContactStore()
        let keys = [CNContactFormatter.descriptorForRequiredKeys(for: .fullName),
                    CNContactEmailAddressesKey,
                    CNContactPhoneNumbersKey,
                    CNContactFamilyNameKey,
                    CNContactGivenNameKey,
                    CNContactMiddleNameKey,
                    CNContactNamePrefixKey,
                    CNContactNameSuffixKey,
                    CNContactPostalAddressesKey,
                    CNContactOrganizationNameKey,
                    CNContactThumbnailImageDataKey,
                    CNContactJobTitleKey] as [Any]
        let fetchRequest = CNContactFetchRequest(keysToFetch: keys as! [CNKeyDescriptor])
        // Set the predicate if there is a query
        if let query = query{
            fetchRequest.predicate = CNContact.predicateForContacts(matchingName: query)
        }
        // Fetch contacts
        do{
            try store.enumerateContacts(with: fetchRequest, usingBlock: { (contact, stop) -> Void in
                contacts.append(contact)
            })
        }
        catch let error as NSError {
            print(error.localizedDescription)
            return []
        }
        // Transform the CNContacts into dictionaries
        var result = [[String:Any]]()
        for contact : CNContact in contacts{
            result.append(contactToDictionary(contact: contact))
        }
        return result
    }
    
    func addContact(contact : CNMutableContact) -> Bool {
        let store = CNContactStore()
        do{
            let saveRequest = CNSaveRequest()
            saveRequest.add(contact, toContainerWithIdentifier: nil)
            try store.execute(saveRequest)
        }
        catch {
            self.flutterResult?(FlutterError(code: "", message: "Failed to add contact", details: error.localizedDescription))
            print(error.localizedDescription)
            return false
        }
        return true
    }
    
    func deleteContact(dictionary : [String:Any]) -> Bool{
        guard let identifier = dictionary["identifier"] as? String else{
            return false;
        }
        let store = CNContactStore()
        let keys = [CNContactIdentifierKey as NSString]
        do{
            if let contact = try store.unifiedContact(withIdentifier: identifier, keysToFetch: keys).mutableCopy() as? CNMutableContact{
                let request = CNSaveRequest()
                request.delete(contact)
                try store.execute(request)
            }
        }
        catch{
            print(error.localizedDescription)
            return false;
        }
        return true;
    }
    
    func dictionaryToContact(dictionary : [String:Any]) -> CNMutableContact{
        let contact = CNMutableContact()
        
        //Simple fields
        contact.givenName = dictionary["givenName"] as? String ?? ""
        contact.familyName = dictionary["familyName"] as? String ?? ""
        contact.middleName = dictionary["middleName"] as? String ?? ""
        contact.namePrefix = dictionary["prefix"] as? String ?? ""
        contact.nameSuffix = dictionary["suffix"] as? String ?? ""
        contact.organizationName = dictionary["company"] as? String ?? ""
        contact.jobTitle = dictionary["jobTitle"] as? String ?? ""
        if ((dictionary["avatar"] as? FlutterStandardTypedData)?.data != nil){
            contact.imageData = (dictionary["avatar"] as? FlutterStandardTypedData)?.data
        }

        //Phone numbers
        if let phoneNumbers = dictionary["phones"] as? [[String:String]]{
            for phone in phoneNumbers where phone["value"] != nil {
               let phoneModel = CNLabeledValue(label: getPhoneLabel(label:phone["label"]),value: CNPhoneNumber(stringValue:phone["value"]!))
                contact.phoneNumbers.append(phoneModel)
            }
        }

        //Emails
        if let emails = dictionary["emails"] as? [[String:String]]{
            for email in emails where nil != email["value"] {
                let emailLabel = email["label"] ?? ""
                contact.emailAddresses.append(CNLabeledValue(label:emailLabel, value:email["value"]! as NSString))
            }
        }

        //Postal addresses
        if let postalAddresses = dictionary["postalAddresses"] as? [[String:String]]{
            for postalAddress in postalAddresses{
                let newAddress = CNMutablePostalAddress()
                newAddress.street = postalAddress["street"] ?? ""
                newAddress.city = postalAddress["city"] ?? ""
                newAddress.postalCode = postalAddress["postcode"] ?? ""
                newAddress.country = postalAddress["country"] ?? ""
                newAddress.state = postalAddress["region"] ?? ""
                let label = postalAddress["label"] ?? ""
                contact.postalAddresses.append(CNLabeledValue(label:label, value:newAddress))
            }
        }
        
        return contact
    }
    
    func contactToDictionary(contact: CNContact) -> [String:Any]{
        
        var result = [String:Any]()
        
        //Simple fields
        result["identifier"] = contact.identifier
        result["displayName"] = CNContactFormatter.string(from: contact, style: CNContactFormatterStyle.fullName)
        result["givenName"] = contact.givenName
        result["familyName"] = contact.familyName
        result["middleName"] = contact.middleName
        result["prefix"] = contact.namePrefix
        result["suffix"] = contact.nameSuffix
        result["company"] = contact.organizationName
        result["jobTitle"] = contact.jobTitle
        if let avatarData = contact.thumbnailImageData {
            result["avatar"] = FlutterStandardTypedData(bytes: avatarData)
        }
        
        //Phone numbers
        var phoneNumbers = [[String:String]]()
        for phone in contact.phoneNumbers{
            var phoneDictionary = [String:String]()
            phoneDictionary["value"] = phone.value.stringValue
            phoneDictionary["label"] = "other"
            if let label = phone.label{
                phoneDictionary["label"] = CNLabeledValue<NSString>.localizedString(forLabel: label)
            }
            phoneNumbers.append(phoneDictionary)
        }
        result["phones"] = phoneNumbers
        
        //Emails
        var emailAddresses = [[String:String]]()
        for email in contact.emailAddresses{
            var emailDictionary = [String:String]()
            emailDictionary["value"] = String(email.value)
            emailDictionary["label"] = "other"
            if let label = email.label{
                emailDictionary["label"] = CNLabeledValue<NSString>.localizedString(forLabel: label)
            }
            emailAddresses.append(emailDictionary)
        }
        result["emails"] = emailAddresses
        
        //Postal addresses
        var postalAddresses = [[String:String]]()
        for address in contact.postalAddresses{
            var addressDictionary = [String:String]()
            addressDictionary["label"] = ""
            if let label = address.label{
                addressDictionary["label"] = CNLabeledValue<NSString>.localizedString(forLabel: label)
            }
            addressDictionary["street"] = address.value.street
            addressDictionary["city"] = address.value.city
            addressDictionary["postcode"] = address.value.postalCode
            addressDictionary["region"] = address.value.state
            addressDictionary["country"] = address.value.country
            
            postalAddresses.append(addressDictionary)
        }
        result["postalAddresses"] = postalAddresses
        
        return result
    }
    
    func getPhoneLabel(label: String?) -> String{
        let labelValue = label ?? ""
        switch(labelValue){
        case "main": return CNLabelPhoneNumberMain
        case "mobile": return CNLabelPhoneNumberMobile
        case "iPhone": return CNLabelPhoneNumberiPhone
        default: return labelValue
        }
    }
    
}
