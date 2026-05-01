---
name: hexagonal-flutter
description: Guía de Clean Architecture (hexagonal adaptada) + DDD para Flutter. Estructura de features, naming conventions, BLoC/Riverpod, repository pattern, testing. Invocar al planificar o revisar apps Flutter.
---

# Clean Architecture + DDD — Flutter

> Flutter no tiene "hexagonal" canónico, pero el principio de Ports & Adapters se aplica perfectamente. La adaptación estándar es Clean Architecture por features con capas domain / data / presentation.

## Estructura de carpetas canónica

```
lib/
├── core/
│   ├── error/
│   │   ├── failure.dart              ← Sealed classes de error (dominio)
│   │   └── exception.dart            ← Excepciones de infraestructura
│   ├── usecase/
│   │   └── usecase.dart              ← Abstract UseCase<Type, Params>
│   ├── network/
│   │   └── network_info.dart         ← Port: ¿hay conectividad?
│   └── injection/
│       └── injection_container.dart  ← get_it / riverpod providers
│
├── features/
│   └── order/                        ← Feature = bounded context
│       ├── domain/
│       │   ├── entity/
│       │   │   └── order.dart        ← Entidad pura (sin Flutter, sin JSON)
│       │   ├── value_object/
│       │   │   └── money.dart
│       │   ├── repository/
│       │   │   └── order_repository.dart  ← Abstract class (port)
│       │   └── usecase/
│       │       ├── place_order.dart
│       │       └── get_order.dart
│       ├── data/
│       │   ├── model/
│       │   │   └── order_model.dart  ← Extiende entity + fromJson/toJson
│       │   ├── datasource/
│       │   │   ├── order_remote_datasource.dart  ← Port (abstract)
│       │   │   ├── order_remote_datasource_impl.dart  ← Dio/http
│       │   │   ├── order_local_datasource.dart   ← Port (abstract)
│       │   │   └── order_local_datasource_impl.dart   ← Drift/Hive
│       │   └── repository/
│       │       └── order_repository_impl.dart    ← Implementa domain port
│       └── presentation/
│           ├── bloc/                 ← o cubit/ o notifier/ (Riverpod)
│           │   ├── order_bloc.dart
│           │   ├── order_event.dart
│           │   └── order_state.dart
│           ├── page/
│           │   └── order_page.dart
│           └── widget/
│               └── order_summary_widget.dart
│
test/
├── features/
│   └── order/
│       ├── domain/
│       │   └── usecase/
│       │       └── place_order_test.dart
│       ├── data/
│       │   └── repository/
│       │       └── order_repository_impl_test.dart
│       └── presentation/
│           └── bloc/
│               └── order_bloc_test.dart
└── fixtures/                         ← JSON fixtures para tests
```

## Reglas de dependencia

```
Presentation → Domain ← Data
     ↓              ↑
  BLoC/Notifier   Repository
  usa UseCases    implementa abstract del dominio
```

**Domain no importa flutter, dio, drift, json_annotation, ni nada externo.**

## Patrones por layer

### Domain — Entity

```dart
// lib/features/order/domain/entity/order.dart
import 'package:equatable/equatable.dart';
import 'money.dart';

// Equatable para comparación por valor
class Order extends Equatable {
  final String id;
  final String customerId;
  final Money total;
  final OrderStatus status;
  final DateTime createdAt;

  const Order({
    required this.id,
    required this.customerId,
    required this.total,
    required this.status,
    required this.createdAt,
  });

  Order copyWith({OrderStatus? status}) {
    return Order(
      id: id,
      customerId: customerId,
      total: total,
      status: status ?? this.status,
      createdAt: createdAt,
    );
  }

  @override
  List<Object> get props => [id, customerId, total, status];
}

enum OrderStatus { pending, confirmed, cancelled }
```

### Domain — Value Object

```dart
// lib/features/order/domain/value_object/money.dart
import 'package:equatable/equatable.dart';

class Money extends Equatable {
  final int amountCents; // evitar doubles para dinero
  final String currency;

  const Money({required this.amountCents, required this.currency});

  Money operator +(Money other) {
    assert(currency == other.currency, 'Currency mismatch');
    return Money(amountCents: amountCents + other.amountCents, currency: currency);
  }

  bool get isZero => amountCents == 0;

  @override
  List<Object> get props => [amountCents, currency];

  @override
  String toString() => '${(amountCents / 100).toStringAsFixed(2)} $currency';
}
```

### Domain — Repository Port

```dart
// lib/features/order/domain/repository/order_repository.dart
import 'package:dartz/dartz.dart';
import '../entity/order.dart';
import '../../../../core/error/failure.dart';

// Port — abstract class, no implementación
abstract class OrderRepository {
  Future<Either<Failure, Order>> placeOrder({
    required String customerId,
    required Money total,
  });

  Future<Either<Failure, Order>> getOrder(String orderId);

  Future<Either<Failure, List<Order>>> getOrdersByCustomer(String customerId);
}
```

### Domain — Use Case

```dart
// lib/features/order/domain/usecase/place_order.dart
import 'package:dartz/dartz.dart';
import '../../../../core/error/failure.dart';
import '../../../../core/usecase/usecase.dart';
import '../entity/order.dart';
import '../repository/order_repository.dart';

class PlaceOrderParams {
  final String customerId;
  final Money total;
  const PlaceOrderParams({required this.customerId, required this.total});
}

class PlaceOrder implements UseCase<Order, PlaceOrderParams> {
  final OrderRepository repository; // depende del port, no la implementación

  const PlaceOrder(this.repository);

  @override
  Future<Either<Failure, Order>> call(PlaceOrderParams params) {
    return repository.placeOrder(
      customerId: params.customerId,
      total: params.total,
    );
  }
}
```

```dart
// lib/core/usecase/usecase.dart
import 'package:dartz/dartz.dart';
import '../error/failure.dart';

abstract class UseCase<Type, Params> {
  Future<Either<Failure, Type>> call(Params params);
}
```

### Data — Model (extiende entity, agrega serialización)

```dart
// lib/features/order/data/model/order_model.dart
import '../../domain/entity/order.dart';
import '../../domain/value_object/money.dart';

class OrderModel extends Order {
  const OrderModel({
    required super.id,
    required super.customerId,
    required super.total,
    required super.status,
    required super.createdAt,
  });

  factory OrderModel.fromJson(Map<String, dynamic> json) {
    return OrderModel(
      id: json['id'] as String,
      customerId: json['customer_id'] as String,
      total: Money(
        amountCents: json['total_cents'] as int,
        currency: json['currency'] as String,
      ),
      status: OrderStatus.values.byName(json['status'] as String),
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'customer_id': customerId,
    'total_cents': total.amountCents,
    'currency': total.currency,
    'status': status.name,
    'created_at': createdAt.toIso8601String(),
  };
}
```

### Data — Repository Implementation

```dart
// lib/features/order/data/repository/order_repository_impl.dart
import 'package:dartz/dartz.dart';
import '../../../../core/error/failure.dart';
import '../../domain/entity/order.dart';
import '../../domain/repository/order_repository.dart';
import '../datasource/order_remote_datasource.dart';
import '../datasource/order_local_datasource.dart';

class OrderRepositoryImpl implements OrderRepository {
  final OrderRemoteDataSource remoteDataSource;
  final OrderLocalDataSource localDataSource;

  const OrderRepositoryImpl({
    required this.remoteDataSource,
    required this.localDataSource,
  });

  @override
  Future<Either<Failure, Order>> placeOrder({
    required String customerId,
    required Money total,
  }) async {
    try {
      final orderModel = await remoteDataSource.placeOrder(
        customerId: customerId,
        totalCents: total.amountCents,
        currency: total.currency,
      );
      await localDataSource.cacheOrder(orderModel);
      return Right(orderModel);
    } on ServerException catch (e) {
      return Left(ServerFailure(e.message));
    } on NetworkException {
      return Left(NetworkFailure());
    }
  }
}
```

### Presentation — BLoC

```dart
// lib/features/order/presentation/bloc/order_bloc.dart
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../domain/usecase/place_order.dart';
import 'order_event.dart';
import 'order_state.dart';

class OrderBloc extends Bloc<OrderEvent, OrderState> {
  final PlaceOrder placeOrder;

  OrderBloc({required this.placeOrder}) : super(OrderInitial()) {
    on<PlaceOrderRequested>(_onPlaceOrderRequested);
  }

  Future<void> _onPlaceOrderRequested(
    PlaceOrderRequested event,
    Emitter<OrderState> emit,
  ) async {
    emit(OrderLoading());
    final result = await placeOrder(PlaceOrderParams(
      customerId: event.customerId,
      total: event.total,
    ));
    result.fold(
      (failure) => emit(OrderError(failure.message)),
      (order) => emit(OrderSuccess(order)),
    );
  }
}
```

### Presentation — Page

```dart
// lib/features/order/presentation/page/order_page.dart
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../bloc/order_bloc.dart';
import '../bloc/order_state.dart';

class OrderPage extends StatelessWidget {
  const OrderPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<OrderBloc, OrderState>(
      listener: (context, state) {
        if (state is OrderError) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(state.message)),
          );
        }
      },
      builder: (context, state) {
        return switch (state) {
          OrderLoading()  => const CircularProgressIndicator(),
          OrderSuccess(order: final o) => OrderSummaryWidget(order: o),
          _               => const OrderForm(),
        };
      },
    );
  }
}
```

## Testing

```dart
// test/features/order/domain/usecase/place_order_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:dartz/dartz.dart';

class MockOrderRepository extends Mock implements OrderRepository {}

void main() {
  late PlaceOrder useCase;
  late MockOrderRepository mockRepository;

  setUp(() {
    mockRepository = MockOrderRepository();
    useCase = PlaceOrder(mockRepository);
  });

  final tOrder = Order(/* ... */);
  final tParams = PlaceOrderParams(customerId: 'c-1', total: Money(amountCents: 5000, currency: 'ARS'));

  test('should return Order when repository succeeds', () async {
    // Arrange
    when(() => mockRepository.placeOrder(
      customerId: any(named: 'customerId'),
      total: any(named: 'total'),
    )).thenAnswer((_) async => Right(tOrder));

    // Act
    final result = await useCase(tParams);

    // Assert
    expect(result, Right(tOrder));
    verify(() => mockRepository.placeOrder(
      customerId: 'c-1',
      total: tParams.total,
    )).called(1);
  });
}
```

## Stack recomendado

| Concern | Library |
|---------|---------|
| State management | [flutter_bloc](https://pub.dev/packages/flutter_bloc) (BLoC/Cubit) o [Riverpod](https://pub.dev/packages/riverpod) |
| Functional errors | [dartz](https://pub.dev/packages/dartz) — `Either<Failure, T>` |
| Equatable | [equatable](https://pub.dev/packages/equatable) — value equality en entities |
| HTTP client | [dio](https://pub.dev/packages/dio) con interceptors |
| Local DB | [drift](https://pub.dev/packages/drift) (SQLite type-safe) |
| DI | [get_it](https://pub.dev/packages/get_it) + [injectable](https://pub.dev/packages/injectable) |
| Mocks | [mocktail](https://pub.dev/packages/mocktail) |
| JSON | `fromJson/toJson` manual en models (o [freezed](https://pub.dev/packages/freezed) para boilerplate) |
| Navigation | [go_router](https://pub.dev/packages/go_router) |

## Riverpod alternative (sin BLoC)

```dart
// Usando Riverpod + AsyncNotifier (Flutter 3.x)
@riverpod
class OrderNotifier extends _$OrderNotifier {
  @override
  AsyncValue<Order?> build() => const AsyncValue.data(null);

  Future<void> placeOrder(PlaceOrderParams params) async {
    state = const AsyncValue.loading();
    final result = await ref.read(placeOrderProvider).call(params);
    state = result.fold(
      (failure) => AsyncValue.error(failure, StackTrace.current),
      (order) => AsyncValue.data(order),
    );
  }
}
```

## Reglas de oro — Flutter

- **Domain = Dart puro** — cero imports de Flutter (material, widgets), cero JSON
- **`Either<Failure, T>`** en repository ports — nunca throw en dominio
- **Models en data layer** — extienden entities del dominio, agregan `fromJson`/`toJson`
- **Un BLoC/Notifier por feature** — no un BLoC global para todo
- **`Equatable`** en entities y states — evita rebuilds innecesarios
- **`const` constructors** donde sea posible — performance
- **Tests de BLoC con `bloc_test`** — `blocTest()` para flujos completos
- **Fixtures JSON** en `test/fixtures/` — no hardcodear JSON en tests
- **`go_router`** para navegación declarativa — no `Navigator.push` directo
