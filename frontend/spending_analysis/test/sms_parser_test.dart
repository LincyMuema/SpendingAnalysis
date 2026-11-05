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