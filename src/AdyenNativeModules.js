import { NativeModules } from 'react-native';
import { find, NATIVE_COMPONENTS } from './ComponentMap';

const UNKNOWN_PAYMENT_METHOD_ERROR =
  'Unknown payment method or native module. \n\n' +
  'Make sure your paymentMethods response contains: ';

const LINKING_ERROR =
  `The package '@adyen/react-native' doesn't seem to be linked. Make sure: \n\n` +
  Platform.select({ ios: "- You have run 'pod install'\n", default: '' }) +
  '- You rebuilt the app after installing the package\n' +
  '- You are not using Expo managed workflow\n';

export const AdyenDropIn = NativeModules.AdyenDropIn
  ? NativeModules.AdyenDropIn
  : new Proxy(
      {},
      { get() { throw new Error(LINKING_ERROR); }, }
    );

export const AdyenInstant = NativeModules.AdyenInstant
  ? NativeModules.AdyenInstant
  : new Proxy(
      {},
      { get() { throw new Error(LINKING_ERROR); }, }
    );

export const AdyenApplePay = NativeModules.AdyenApplePay
  ? NativeModules.AdyenApplePay
  : new Proxy(
      {},
      { get() { throw new Error(LINKING_ERROR); }, }
    );

export const AdyenGooglePay = NativeModules.AdyenGooglePay
  ? NativeModules.AdyenGooglePay
  : new Proxy(
      {},
      { get() { throw new Error(LINKING_ERROR); }, }
    );

export function getNativeComponent(name, paymentMethods) {
  const type = name.toLowerCase();
  switch (type) {
    case 'dropin':
    case 'drop-in':
    case 'adyendropin':
      return { nativeComponent: AdyenDropIn };
    case 'applepay':
    case 'apple-pay':
      return { nativeComponent: AdyenApplePay };
    case 'paywithgoogle':
    case 'googlepay':
    case 'google-pay':
      return { nativeComponent: AdyenGooglePay };
    default:
      break;
  }

  let paymentMethod = find(paymentMethods, type)
  if (!paymentMethod) {
    throw new Error(UNKNOWN_PAYMENT_METHOD_ERROR + name);
  }

  if (NATIVE_COMPONENTS.includes(type)) {
    return { nativeComponent: AdyenDropIn, paymentMethod: paymentMethod };
  }

  return { nativeComponent: AdyenInstant, paymentMethod: paymentMethod };
}
