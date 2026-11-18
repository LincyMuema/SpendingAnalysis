import 'package:flutter_test/flutter_test.dart';
import 'package:spending_analysis/sms_parser.dart';

void main() {
  group('M-Pesa', () {
    test('paid to a till / merchant', () {
      final r = SmsParser.parse(
          'TST0000A01 Confirmed. Ksh1,779.00 paid to CARREFOUR GLR 03. on 25/10/26 at 2:06 PM.New M-PESA balance is Ksh1,000.00. Transaction cost, Ksh0.00. Amount you can transact within the day is 500,000.00. See all your balances now https://saf.cx/')!;
      expect(r.reference, 'TST0000A01');
      expect(r.amount, 1779.00);
      expect(r.date, '2026-10-25');
      expect(r.source, 'MPESA');
      expect(r.counterparty, 'CARREFOUR GLR 03');
      expect(r.category, 'Shopping');
      expect(r.isExpense, true);
    });

    test('paid to a restaurant', () {
      final r = SmsParser.parse(
          'TST0000A02 Confirmed. Ksh400.00 paid to FOOD AND US LIMITED. on 30/10/26 at 5:03 PM.New M-PESA balance is Ksh1,000.00. Transaction cost, Ksh0.00.')!;
      expect(r.amount, 400.00);
      expect(r.date, '2026-10-30');
      expect(r.category, 'Food & Dining');
    });

    test('paid to an "enterprises" shop', () {
      final r = SmsParser.parse(
          'TST0000A03 Confirmed. Ksh45.00 paid to FRANCY ENTERPRISES. on 28/10/26 at 1:41 PM.New M-PESA balance is Ksh1,000.00.')!;
      expect(r.amount, 45.00);
      expect(r.category, 'Shopping');
    });

    test('buy goods: the teller number is removed', () {
      final r = SmsParser.parse(
          'TST0000A06 Confirmed. Ksh480.00 paid to CHINA SQUARE LANGATA TELLER 1. on 18/11/26 at 7:08 PM.New M-PESA balance is Ksh1,000.00. Transaction cost, Ksh0.00. Amount you can transact within the day is 499,480.00. See all your balances now https://saf.cx/')!;
      expect(r.amount, 480.00);
      expect(r.date, '2026-11-18');
      expect(r.counterparty, 'CHINA SQUARE LANGATA');
      expect(r.category, 'Shopping');
    });

    test('paybill: the account number is removed', () {
      final r = SmsParser.parse(
          'TST0000A07 Confirmed. Ksh40.00 sent to LIPAKITU LIMITED for account 1234 on 18/11/26 at 7:42 AM New M-PESA balance is Ksh1,000.00. Transaction cost, Ksh0.00.Amount you can transact within the day is 499,960.00. See all your balances now https://saf.cx/')!;
      expect(r.reference, 'TST0000A07');
      expect(r.amount, 40.00);
      expect(r.counterparty, 'LIPAKITU LIMITED');
      expect(r.isExpense, true);
    });

    test('money received: masked phone number removed, not an expense', () {
      final r = SmsParser.parse(
          'TST0000A08 Confirmed.You have received Ksh100.00 from MARY  WANJIRU 0700***000 on 18/11/26 at 10:34 AM  New M-PESA balance is Ksh1,000.00. Invest & earn daily interest with ZIIDI on https://saf.cx/')!;
      expect(r.amount, 100.00);
      expect(r.counterparty, 'MARY WANJIRU');
      expect(r.isExpense, false);
    });

    test('airtime (lower-case "confirmed")', () {
      final r = SmsParser.parse(
          'TST0000A09 confirmed.You bought Ksh5.00 of airtime on 18/11/26 at 9:58 PM.New M-PESA balance is Ksh1,000.00. Transaction cost, Ksh0.00. Amount you can transact within the day is 499,475.00. See all your balances now https://saf.cx/')!;
      expect(r.reference, 'TST0000A09');
      expect(r.amount, 5.00);
      expect(r.date, '2026-11-18');
      expect(r.counterparty, 'Airtime');
      expect(r.category, 'Bills & Utilities');
    });
  });

  group('Airtel Money', () {
    const sms =
        'AT0000000B1. Ksh 100 sent to JANE DOE 07xxxxxxxx on 31/10/26 at 11:59 PM. Fee: Ksh 0. Bal: Ksh 1,000.0. MPESA ID: TST0000A04';

    test('parsed as wallet payment', () {
      final r = SmsParser.parse(sms)!;
      expect(r.reference, 'AT0000000B1');
      expect(r.amount, 100);
      expect(r.date, '2026-10-31');
      expect(r.source, 'WALLET');
      expect(r.counterparty, 'JANE DOE');
    });

    test('transfer to yourself is not an expense', () {
      final r = SmsParser.parse(sms, ownName: 'Jane Doe')!;
      expect(r.isExpense, false);
    });
  });

  group('I&M Bank card', () {
    test('purchase', () {
      final r = SmsParser.parse(
          'Dear JANE, You made a purchase ofKES 539.00 on 2026-10-02 20:31:19 at QUICK MART LIMITED using I&M 4111********1111. If you did not effect the transaction, urgently contact us on 0719088000 or Toll Free 0800721088.')!;
      expect(r.amount, 539.00);
      expect(r.date, '2026-10-02');
      expect(r.source, 'CARD');
      expect(r.counterparty, 'QUICK MART LIMITED');
      expect(r.category, 'Shopping');
    });

    test('large purchase with thousands separator', () {
      final r = SmsParser.parse(
          'Dear JANE, You made a purchase ofKES 5,400.00 on 2026-10-07 15:55:00 at PINS ENTERTAINMENT using I&M 4111********1111. If you did not effect the transaction, urgently contact us on 0719088000 or Toll Free 0800721088.')!;
      expect(r.amount, 5400.00);
      expect(r.category, 'Entertainment');
    });

    test('merchant with an asterisk', () {
      final r = SmsParser.parse(
          'Dear JANE, You made a purchase ofKES 650.00 on 2026-10-07 14:17:01 at PesaPal*Kuku Foods Ken using I&M 4111********1111. If you did not effect the transaction, urgently contact us on 0719088000.')!;
      expect(r.counterparty, 'PesaPal*Kuku Foods Ken');
      expect(r.category, 'Food & Dining');
    });
  });

  // Formats below come from real messages; names, references and account
  // numbers have been replaced.
  group('Co-operative Bank', () {
    const sms =
        'Please NEVER share your PIN, PASSWORD, any codes or CARD details with ANYONE! not even people who may claim to be bank staff. Ref:AC00000TEST1: Dear JANE, MPESA transfer of KES 1200 to MARY ANNE WANJIKU-2547 at 05-11-2026 04:24 PM was successful.MPESA Ref:TST0000C01.';

    test('M-Pesa transfer from the bank account', () {
      final r = SmsParser.parse(sms)!;
      expect(r.reference, 'TST0000C01');
      expect(r.amount, 1200);
      expect(r.date, '2026-11-05');
      expect(r.source, 'CARD');
      expect(r.counterparty, 'MARY ANNE WANJIKU');
      expect(r.isExpense, true);
    });

    test('transfer to your own M-Pesa is not an expense', () {
      final r = SmsParser.parse(
          'Ref:AC00000TEST2: Dear JANE, MPESA transfer of KES 100 to Jane Wambui Doe-2547 at 10-11-2026 09:40 AM was successful.MPESA Ref:TST0000C02.',
          ownName: 'Jane Doe')!;
      expect(r.isExpense, false);
    });
  });

  group('Absa', () {
    test('card debit, merchant from the fixed-width field', () {
      final r = SmsParser.parse(
          'Dear Customer a Debit has been made for KES3400 in Account ending XX0000 AT POS BALTIC TEXTILE TRADING LTNAIROBI      KE. please call 0700000000 for any enquiries',
          today: DateTime(2026, 11, 8))!;
      expect(r.amount, 3400);
      expect(r.date, '2026-11-08'); // no date in the message: the day it arrived
      expect(r.source, 'CARD');
      expect(r.counterparty, 'BALTIC TEXTILE TRADING LT');
      expect(r.category, 'Shopping');
    });

    test('fuel station', () {
      final r = SmsParser.parse(
          'Dear Customer a Debit has been made for KES3000 in Account ending XX0000 AT POS RUBIS LANGATA ROAD       NAIROBI      KE. please call 0700000000 for any enquiries')!;
      expect(r.counterparty, 'RUBIS LANGATA ROAD');
      expect(r.category, 'Transport');
    });

    test('credit is not an expense', () {
      final r = SmsParser.parse(
          'Dear Customer a Credit has been made for KES60000 on your Account XX0000 VIA Digital/Branch Banking please call 0700000000 for any enquiries')!;
      expect(r.isExpense, false);
    });
  });

  group('Standard Chartered', () {
    test('card payment', () {
      final r = SmsParser.parse(
          'Dear Client, a transaction of KES 1200.00 was made on card ending 0000 at MILWAYS INTERIOR on 2026-10-30. For any queries call +254 20 0000000')!;
      expect(r.amount, 1200.00);
      expect(r.date, '2026-10-30');
      expect(r.source, 'CARD');
      expect(r.counterparty, 'MILWAYS INTERIOR');
      expect(r.isExpense, true);
    });

    test('Google subscriptions and pending card holds are tidied', () {
      final yt = SmsParser.parse(
          'Dear Client, a transaction of KES 289.00 was made on card ending 0000 at GOOGLE YouTubePremium on 2026-10-28. For any queries call +254 20 0000000')!;
      expect(yt.counterparty, 'YouTubePremium');
      expect(yt.category, 'Entertainment');
      final one = SmsParser.parse(
          'Dear Client, a transaction of KES 273.14 was made on card ending 0000 at GOOGLE Google One on 2026-11-03. For any queries call +254 20 0000000')!;
      expect(one.amount, 273.14);
      expect(one.counterparty, 'Google One');
      expect(one.category, 'Bills & Utilities');
      final uber = SmsParser.parse(
          'Dear Client, a transaction of KES 222.00 was made on card ending 0000 at UBER PENDING on 2026-11-01. For any queries call +254 20 0000000')!;
      expect(uber.counterparty, 'UBER');
      expect(uber.category, 'Transport');
    });

    test('transfer to M-Pesa uses the M-Pesa code', () {
      final r = SmsParser.parse(
          'Dear Client, transaction of KES 1509.00 to MPESA has been processed successfully, ref. TST0000S01 to JOHN KAMAU For any queries contact us on  +254 20 0000000',
          today: DateTime(2026, 11, 2))!;
      expect(r.reference, 'TST0000S01');
      expect(r.amount, 1509.00);
      expect(r.date, '2026-11-02');
      expect(r.counterparty, 'JOHN KAMAU');
      expect(r.isExpense, true);
    });

    test('transfer to your own M-Pesa is not an expense', () {
      final r = SmsParser.parse(
          'Dear Client, transaction of KES 1509.00 to MPESA has been processed successfully, ref. TST0000S02 to JOHN KAMAU For any queries contact us on +254 20 0000000',
          ownName: 'John Kamau')!;
      expect(r.isExpense, false);
    });

    test('the second notice of the same M-Pesa transfer is skipped', () {
      expect(
          SmsParser.parse(
              'Good day, JOHN KAMAU has transferred KES 1509.00 to your MPESA Account, ref  TST0000S01. For any queries, call us on 254 20 0000000'),
          isNull);
    });

    test('account to account transfer', () {
      final r = SmsParser.parse(
          'Dear Client, KES 9000.00 was transferred from Acc. ending with 1111 to Acc. ending with 2222. For any queries call +254 20 0000000')!;
      expect(r.amount, 9000.00);
      expect(r.counterparty, 'Account ending 2222');
      expect(r.category, 'Transfer');
    });

    test('service notice is ignored', () {
      expect(
          SmsParser.parse(
              'Dear Client, as part of scheduled system enhancements, ATM services will be unavailable tomorrow, 31 October 2026, from 6:30 am to 9:30 am. Online Banking and the SC Mobile app will be unavailable from 3:30 am to 7:30 am. Thank you for banking with Standard Chartered.',
              sender: 'StanChart'),
          isNull);
    });
  });

  group('Categories', () {
    test('person names are not mistaken for keywords', () {
      expect(SmsParser.categorise('SHARON WANJIKU'), 'Other');
      expect(SmsParser.categorise('MARTIN OTIENO'), 'Other');
    });

    test('keywords match the start of a word only', () {
      expect(SmsParser.categorise('PARENTS ASSOCIATION'), 'Other'); // not "rent"
      expect(SmsParser.categorise('NAIVAS WESTLANDS'), 'Shopping');
      expect(SmsParser.categorise('KENYA POWER'), 'Bills & Utilities');
    });
  });

  group('Edge cases', () {
    test('unrelated message returns null', () {
      expect(SmsParser.parse('Your Safaricom data bundle expires tomorrow.'), isNull);
    });

    test('M-Pesa mini-statement is skipped (not double counted)', () {
      expect(
          SmsParser.parse(
              'TST0000A05 [20260728; ;Customer Send Money; 25****abc;Ksh30.00]Completed [20260727; ;Customer Payment to Pochi; 07****def;Ksh50.00]Completed [20260727; ;KenyaRecharge; 4093441 - SAFARICOM DATA BUNDLES;Ksh20.00]Completed Transaction cost, Ksh0.00.'),
          isNull);
    });

    test('empty message returns null', () {
      expect(SmsParser.parse('   '), isNull);
    });

    test('money received is not an expense', () {
      final r = SmsParser.parse(
          'UJAAA11111 Confirmed.You have received Ksh1,000.00 from JOHN DOE 0712345678 on 12/10/26 at 3:45 PM. New M-PESA balance is Ksh2,000.00.')!;
      expect(r.isExpense, false);
      expect(r.amount, 1000.00);
    });

    test('fallback never uses a time as the merchant', () {
      final r = SmsParser.parse(
          'XYZ1234567 Confirmed. Ksh250.00 withdrawn on 20/10/26 at 2:06 PM. New M-PESA balance is Ksh100.00.',
          sender: 'MPESA')!;
      expect(r.counterparty, 'M-Pesa payment');
      expect(r.source, 'MPESA');
      expect(r.isFallback, true);
    });

    test('terminal number is trimmed from merchant name', () {
      final r = SmsParser.parse(
          'Your account has been debited with KES 550.00 at SIMBISA WESTGATE733964 on 2026-07-31.')!;
      expect(r.counterparty, 'SIMBISA WESTGATE');
    });

    test('unseen bank alert handled by fallback', () {
      final r = SmsParser.parse(
          'Your account has been debited with KES 1,200.00 at JAVA HOUSE on 2026-10-20.')!;
      expect(r.amount, 1200.00);
      expect(r.source, 'CARD');
      expect(r.category, 'Food & Dining');
    });
  });
}