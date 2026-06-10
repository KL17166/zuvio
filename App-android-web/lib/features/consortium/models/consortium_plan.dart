class ConsortiumPlan {
  final String id;
  final String name;
  final int durationMonths;
  final double adminFeeRate; // Taxa administrativa
  final double fundRate; // Fundo de reserva
  final double monthlyInstallment; // Valor da parcela (Calculado no server)

  const ConsortiumPlan({
    required this.id,
    required this.name,
    required this.durationMonths,
    required this.adminFeeRate,
    required this.fundRate,
    required this.monthlyInstallment,
  });

  factory ConsortiumPlan.fromJson(Map<String, dynamic> json) {
    T? safe<T>(dynamic v) {
      if (v == null) return null;
      if (v is T) return v;
      if (v is num) {
        if (T == double) return v.toDouble() as T;
        if (T == int) return v.toInt() as T;
      }
      if (T == String) return v.toString() as T;
      return null;
    }

    return ConsortiumPlan(
      id: safe<String>(json['id']) ?? '',
      name: safe<String>(json['name']) ?? 'Plano',
      durationMonths: safe<int>(json['durationMonths']) ?? 12,
      adminFeeRate: safe<double>(json['adminFeeRate']) ?? 0.0,
      fundRate: safe<double>(json['fundRate']) ?? 0.0,
      monthlyInstallment: safe<double>(json['monthlyInstallment']) ?? 0.0,
    );
  }

  // Nome formatado do plano
  String get displayName => '$durationMonths meses';

  // Taxa formatada (combina admin + fundo se quiser, ou só admin)
  String get taxRateFormatted => '${adminFeeRate.toStringAsFixed(2)}%';
}
