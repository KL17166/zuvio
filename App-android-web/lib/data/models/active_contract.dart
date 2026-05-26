import 'package:katari/data/models/product.dart';

class ActiveContract {
  final Product product;
  final int totalInstallments;
  final int currentInstallment;
  final double nextPaymentAmount;
  final DateTime dueDate;
  final String status;
  final DateTime contractDate;
  final String groupNumber;
  final String quotaNumber;
  final double creditValue;
  final double administrationFee;

  final Set<int> paidInstallments;
  final Map<int, double> installmentValues;
  final Map<int, String> installmentIds;
  final Map<int, DateTime> installmentDueDates;
  final Map<int, String> installmentTokens;

  ActiveContract({
    required this.product,
    required this.totalInstallments,
    required this.currentInstallment,
    required this.nextPaymentAmount,
    required this.dueDate,
    required this.status,
    required this.contractDate,
    String? groupNumber,
    String? quotaNumber,
    double? creditValue,
    double? administrationFee,
    Set<int>? paidInstallments,
    Map<int, double>? installmentValues,
    Map<int, String>? installmentIds,
    Map<int, DateTime>? installmentDueDates,
    Map<int, String>? installmentTokens,
  })  : groupNumber = groupNumber ?? '${product.hashCode % 1000 + 1}',
        quotaNumber = quotaNumber ?? '${product.hashCode % 200 + 1}',
        creditValue = creditValue ?? product.price,
        administrationFee = administrationFee ?? 0.10, // 10% padrão
        paidInstallments = paidInstallments ?? {},
        installmentValues = installmentValues ?? {},
        installmentIds = installmentIds ?? {},
        installmentDueDates = installmentDueDates ?? {},
        installmentTokens = installmentTokens ?? {};

  double get progressPercentage =>
      (paidInstallmentsCount / totalInstallments) * 100;

  int get remainingInstallments => totalInstallments - paidInstallmentsCount;

  bool get isActive => status == 'active';

  int get paidInstallmentsCount => paidInstallments.length;

  int get nextInstallmentIndex {
    // Retorna o primeiro índice (1-based) que não está no set de pagos
    for (int i = 1; i <= totalInstallments; i++) {
      if (!paidInstallments.contains(i)) return i;
    }
    return totalInstallments + 1; // Tudo pago
  }

  /// Retorna o valor da parcela, já calculado pelo servidor (com descontos/multas)
  double getInstallmentValue(int installmentIndex) {
    if (installmentValues.containsKey(installmentIndex)) {
      return installmentValues[installmentIndex]!;
    }
    return nextPaymentAmount;
  }

  // Adesão conta como pagamento apenas se está no set de pagos (installment 0)
  bool get isAdesaoPaid => paidInstallments.contains(1);

  int get totalPaymentsCount => paidInstallmentsCount;

  double get totalPaid {
    if (installmentValues.isEmpty) {
      return nextPaymentAmount * totalPaymentsCount;
    }
    return paidInstallments.fold(0.0, (sum, idx) {
      return sum + (installmentValues[idx] ?? nextPaymentAmount);
    });
  }

  double get totalAdminFeePaid => totalPaid * administrationFee;

  double get totalReserveFundPaid => totalPaid * 0.02;

  double get commonFundPaid =>
      totalPaid - totalAdminFeePaid - totalReserveFundPaid;

  factory ActiveContract.fromJson(Map<String, dynamic> json) {
    // Helper para parsear números
    double toDouble(dynamic val) {
      if (val == null) return 0.0;
      if (val is int) return val.toDouble();
      return val as double;
    }

    // Helper para parsear datas
    DateTime toDate(dynamic val) {
      if (val == null) return DateTime.now();
      return DateTime.tryParse(val.toString()) ?? DateTime.now();
    }

    // Parse paid installments and values from API
    Set<int> paid = {};
    Map<int, double> values = {};
    Map<int, String> ids = {};
    Map<int, DateTime> dueDates = {};
    Map<int, String> tokens = {};

    if (json['installments'] != null) {
      for (var inst in json['installments']) {
        int number = inst['number'];
        if (inst['status'] == 'PAID') {
          paid.add(number);
        }
        // Store installment ID for PIX generation
        if (inst['id'] != null) {
          ids[number] = inst['id'].toString();
        }
        // Store idTokenPay for PIX payment verification
        if (inst['idTokenPay'] != null) {
          tokens[number] = inst['idTokenPay'].toString();
        }
        // Store due date from server
        if (inst['dueDate'] != null) {
          dueDates[number] =
              DateTime.tryParse(inst['dueDate'].toString()) ?? DateTime.now();
        }
        // Capture calculated value from server
        if (inst['valueToPay'] != null) {
          values[number] = toDouble(inst['valueToPay']);
        } else if (inst['amount'] != null) {
          values[number] = toDouble(inst['amount']);
        }
      }
    } else if (json['paidInstallments'] is List) {
      paid = (json['paidInstallments'] as List).map((e) => e as int).toSet();
    }

    // Product Parsing
    // Now backend correctly sends 'product' nested in plan, or at root.
    // 'motorcycle' is kept only as a deep fallback for old cached data.
    var productJson = json['product'] ?? json['plan']?['product'] ??
        json['plan']?['motorcycle'] ?? json['motorcycle'];

    // Determine next payoff value
    double monthlyVal = toDouble(json['plan']?['monthlyInstallment']);

    // If plan value is 0, try to get from first installment
    if (monthlyVal <= 0 && values.isNotEmpty) {
      // Find the first unpaid installment value or the first one in general
      final sortedIndices = values.keys.toList()..sort();
      if (sortedIndices.isNotEmpty) {
        monthlyVal = values[sortedIndices.first]!;
      }
    }

    // Final fallback to credit / installments calculation
    if (monthlyVal <= 0) {
      double credit = toDouble(json['creditValue']);
      int total =
          json['plan']?['durationMonths'] ?? json['totalInstallments'] ?? 60;
      if (total > 0) monthlyVal = credit / total;
    }

    // Parse administration fee from API (default 10%)
    double adminFee = 0.10;
    if (json['administrationFee'] != null) {
      adminFee = toDouble(json['administrationFee']);
    } else if (json['plan']?['adminFeeRate'] != null) {
      adminFee = toDouble(json['plan']['adminFeeRate']);
    }

    return ActiveContract(
      product: Product.fromJson(productJson ?? {}),
      totalInstallments:
          json['plan']?['durationMonths'] ?? json['totalInstallments'] ?? 60,
      currentInstallment: (paid.length) + 1,
      nextPaymentAmount: monthlyVal,
      dueDate: _findNextDueDate(dueDates, paid) ??
          DateTime.now().add(const Duration(days: 10)),
      status: json['status']?.toString().toLowerCase() ?? 'active',
      contractDate: toDate(json['createdAt']),
      groupNumber: json['groupNumber'],
      quotaNumber: json['quotaNumber'],
      creditValue: toDouble(json['creditValue']),
      administrationFee: adminFee,
      paidInstallments: paid,
      installmentValues: values,
      installmentIds: ids,
      installmentDueDates: dueDates,
      installmentTokens: tokens,
    );
  }

  /// Finds the due date of the next unpaid installment from server data
  static DateTime? _findNextDueDate(
      Map<int, DateTime> dueDates, Set<int> paid) {
    if (dueDates.isEmpty) return null;
    final sortedKeys = dueDates.keys.toList()..sort();
    for (final key in sortedKeys) {
      if (!paid.contains(key)) return dueDates[key];
    }
    return null; // All paid
  }
}
