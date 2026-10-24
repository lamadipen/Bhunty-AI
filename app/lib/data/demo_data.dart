import '../core/money.dart';
import '../core/qty.dart';
import 'models.dart';
import 'shop_store.dart';

/// Sample catalog from the prototype. Also used to seed a brand-new Firebase
/// shop so the tap grid is not empty before catalog editing exists.
/// Product ids are fixed so the demo AI scripts can refer to them.
List<Product> demoProducts() {
  Product p(
    String id,
    String ne,
    String en,
    int price,
    int cost,
    Unit unit,
    int stock,
    int lowAt,
    String letter,
    int bg,
    int ink,
  ) => Product(
    id: id,
    nameNe: ne,
    nameEn: en,
    pricePaisa: rs(price),
    costPaisa: rs(cost),
    unit: unit,
    stockMilli: stock * milli,
    lowStockAtMilli: lowAt * milli,
    letter: letter,
    tileBg: bg,
    tileInk: ink,
    barcode: 'demo-$id',
  );

  return [
    p(
      'waiwai',
      'वाइवाइ',
      'Wai Wai',
      25,
      18,
      Unit.packet,
      6,
      12,
      'वा',
      0xFFF6E3B4,
      0xFF6B4A00,
    ).withPack('कार्टुन', 30 * milli),
    p('egg', 'अण्डा', 'Egg', 20, 16, Unit.piece, 90, 30, 'अ', 0xFFF3E7DA, 0xFF6A3F17),
    p('milk', 'दूध', 'Milk', 55, 48, Unit.packet, 20, 10, 'दू', 0xFFDCE8F5, 0xFF1E3E73),
    p('sugar', 'चिनी', 'Sugar', 120, 105, Unit.kg, 3, 5, 'चि', 0xFFEAE6F4, 0xFF3E2F73),
    p('rice', 'चामल', 'Rice', 90, 78, Unit.kg, 60, 20, 'चा', 0xFFE3F0E8, 0xFF14512F),
    p('oil', 'तेल', 'Oil', 280, 250, Unit.litre, 2, 4, 'ते', 0xFFF6EBC9, 0xFF5E4B00),
    p('soap', 'साबुन', 'Soap', 60, 45, Unit.piece, 18, 6, 'सा', 0xFFF5DDE6, 0xFF7A1F45),
    p('biscuit', 'बिस्कुट', 'Biscuit', 30, 22, Unit.packet, 40, 12, 'बि', 0xFFF1E2D3, 0xFF6A3F17),
  ];
}

/// The prototype's demo shop (in memory), so every screen has something to show.
ShopStore demoStore({DateTime Function()? clock}) {
  final now = (clock ?? DateTime.now)();
  final products = demoProducts();
  final byId = {for (final x in products) x.id: x};

  final customers = [
    Customer(id: 'ram', name: 'राम दाइ', initial: 'रा', balancePaisa: rs(3200), lastNote: 'हिजो · चामल, तेल'),
    Customer(id: 'sita', name: 'सीता दिदी', initial: 'सी', balancePaisa: rs(850), lastNote: '३ दिन अघि · दूध'),
    Customer(id: 'hotel', name: 'होटल नमस्ते', initial: 'हो', balancePaisa: rs(8350), lastNote: 'आज · चिनी २५ केजी'),
    Customer(id: 'bikash', name: 'विकास', initial: 'वि', balancePaisa: 0, lastNote: 'सबै तिर्यो'),
    Customer(id: 'maya', name: 'माया आमा', initial: 'मा', balancePaisa: 0, lastNote: 'सबै तिर्यो'),
  ];

  // Earlier today: रु 3,100 cash + रु 1,150 QR, as on the prototype's home screen.
  Sale seeded(String id, PaymentMethod method, Map<String, int> qty) {
    final lines = [
      for (final e in qty.entries)
        SaleLine(
          productId: e.key,
          name: byId[e.key]!.nameNe,
          qtyMilli: e.value * milli,
          pricePaisa: byId[e.key]!.pricePaisa,
          lineTotalPaisa: lineTotal(byId[e.key]!.pricePaisa, e.value * milli),
        ),
    ];
    final total = lines.fold(0, (s, l) => s + l.lineTotalPaisa);
    return Sale(id: id, lines: lines, totalPaisa: total, method: method, createdAt: now);
  }

  return ShopStore(
    shopName: 'राम किराना पसल',
    products: products,
    customers: customers,
    sales: [
      seeded('seed-cash', PaymentMethod.cash, {'waiwai': 42, 'rice': 10, 'sugar': 5, 'egg': 20, 'biscuit': 5}),
      seeded('seed-qr', PaymentMethod.qr, {'oil': 3, 'soap': 4, 'biscuit': 1, 'egg': 2}),
    ],
    clock: clock,
  );
}
