//
// Copyright (c) 2021 Adyen N.V.
//
// This file is open source and available under the MIT license. See the LICENSE file for more info.
//

import Adyen
import Foundation
import PassKit
import React

@objc(AdyenDropIn)
internal final class DropInModule: BaseModule {

    private var lookupHandler: (([LookupAddressModel]) -> Void)?
    private var lookupCompliationHandler: ((Result<PostalAddress, any Error>) -> Void)?

    override public func supportedEvents() -> [String]! { Events.allCases.map(\.rawValue) }

    private var dropInComponent: DropInComponent? {
        currentComponent as? DropInComponent
    }

    @objc
    func hide(_ success: NSNumber, event: NSDictionary) {
        dismiss(success.boolValue)
    }

    @objc
    func update(_ results: NSArray) {
        guard let lookupHandler else { return }

        let addressModels: [LookupAddressModel] = results.compactMap{ $0 as? NSDictionary }.compactMap { try? $0.toJson() }
        DispatchQueue.main.async {
            lookupHandler(addressModels)
        }
    }

    @objc
    func confirm(_ success: NSNumber, address: NSDictionary) {
        guard let lookupCompliationHandler else { return }

        DispatchQueue.main.async {
            if !success.boolValue, let message = address["message"] as? String {
                return lookupCompliationHandler(.failure(AddressError(message: message) ))
            }

            do {
                let address: LookupAddressModel = try address.toJson()
                lookupCompliationHandler(.success(address.postalAddress))
            } catch {
                lookupCompliationHandler(.failure(error))
            }
        }
    }

    @objc
    func open(_ paymentMethodsDict: NSDictionary, configuration: NSDictionary) {
        let parser = RootConfigurationParser(configuration: configuration)
        let paymentMethods: PaymentMethods
        let context: AdyenContext
        do {
            paymentMethods = try parsePaymentMethods(from: paymentMethodsDict)
            context = try parser.fetchContext(session: BaseModule.session)
        } catch {
            return sendEvent(error: error)
        }

        let dropInConfigParser = DropInConfigurationParser(configuration: configuration)
        let config = dropInConfigParser.configuration
        config.card = CardConfigurationParser(configuration: configuration, delegate: self).dropinConfiguration
        config.style = AdyenAppearanceLoader.findStyle() ?? DropInComponent.Style()
        if let locale = BaseModule.session?.sessionContext.shopperLocale ?? parser.shopperLocale {
            config.localizationParameters = LocalizationParameters(enforcedLocale: locale)
        }
        if let requestorAppUrl = ThreeDS2ConfigurationParser(configuration: configuration).requestorAppUrl,
           let url = URL(string: requestorAppUrl) {
            config.actionComponent.threeDS.requestorAppURL = url
        }

        if let payment = context.payment {
            (try? ApplepayConfigurationParser(configuration: configuration).buildConfiguration(payment: payment)).map {
                config.applePay = $0
            }
        }

        SessionHelperModule.sessionListener = self
        let component = DropInComponent(paymentMethods: paymentMethods,
                                        context: context,
                                        configuration: config,
                                        title: dropInConfigParser.title)
        currentComponent = component
        component.delegate = BaseModule.session ?? self
        component.partialPaymentDelegate = BaseModule.session
        present(component: component)
    }

    @objc
    func handle(_ dictionary: NSDictionary) {
        let action: Action
        do {
            action = try parseAction(from: dictionary)
        } catch {
            return sendEvent(error: error)
        }

        DispatchQueue.main.async { [weak self] in
            self?.dropInComponent?.handle(action)
        }
    }

    @objc
    func getReturnURL(_ resolver: @escaping RCTPromiseResolveBlock,
                      rejecter: @escaping RCTPromiseRejectBlock) {
        resolver(nil)
    }

    override func cleanUp() {
        lookupHandler = nil
        lookupCompliationHandler = nil
        super.cleanUp()
    }

}

extension DropInModule: DropInComponentDelegate {
    func didSubmit(_ data: Adyen.PaymentComponentData, from component: Adyen.PaymentComponent, in dropInComponent: Adyen.AnyDropInComponent) {
        let response: SubmitData
        if let appleData = data.paymentMethod as? ApplePayDetails {
            response = SubmitData(paymentData: data.jsonObject, extra: appleData.extraData)
        } else {
            response = SubmitData(paymentData: data.jsonObject, extra: nil)
        }
        sendEvent(event: .didSubmit, body: response.jsonObject)
    }

    func didFail(with error: Error, from component: Adyen.PaymentComponent, in dropInComponent: Adyen.AnyDropInComponent) {
        sendEvent(error: error)
    }

    func didProvide(_ data: Adyen.ActionComponentData, from component: Adyen.ActionComponent, in dropInComponent: Adyen.AnyDropInComponent) {
        sendEvent(event: .didProvide, body: data.jsonObject)
    }

    func didComplete(from component: Adyen.ActionComponent, in dropInComponent: Adyen.AnyDropInComponent) {
        sendEvent(event: .didComplete, body: nil)
    }

    func didFail(with error: Error, from component: Adyen.ActionComponent, in dropInComponent: Adyen.AnyDropInComponent) {
        sendEvent(error: error)
    }

    func didFail(with error: Error, from dropInComponent: Adyen.AnyDropInComponent) {
        sendEvent(error: error)
    }
}

extension DropInModule: AddressLookupProvider {

    func lookUp(searchTerm: String, resultHandler: @escaping ([LookupAddressModel]) -> Void) {
        lookupHandler = resultHandler
        sendEvent(event: .didUpdateAddress, body: searchTerm)
    }

    func complete(incompleteAddress: LookupAddressModel, resultHandler: @escaping (Result<PostalAddress, any Error>) -> Void) {
        lookupCompliationHandler = resultHandler
        sendEvent(event: .didConfirmAddress, body: incompleteAddress.jsonObject)
    }

}

struct AddressError: Error, LocalizedError, Codable {

    var errorDescription: String? {
        message
    }

    var message: String

    enum CodingKeys: CodingKey {
        case message
    }
}
