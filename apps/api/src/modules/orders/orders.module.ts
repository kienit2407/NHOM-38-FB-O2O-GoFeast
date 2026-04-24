import { Module } from '@nestjs/common';
import { MongooseModule } from '@nestjs/mongoose';

import { DeliveryCheckoutController } from './controllers/delivery-checkout.controller';
import { DineInCheckoutController } from './controllers/dinein-checkout.controller';

import { CheckoutPricingService } from './services/checkout-pricing.service';
import { PromotionEngineService } from './services/promotion-engine.service';
import { OrderFactoryService } from './services/order-factory.service';

import { Order, OrderSchema } from './schemas/order.schema';

import { Payment, PaymentSchema } from '../payments/schemas/payment.schema';
import { Merchant, MerchantSchema } from '../merchants/schemas/merchant.schema';
import { Product, ProductSchema } from '../merchants/schemas/product.schema';

// nếu project bạn export từ barrel khác thì sửa lại path này
import { TableSession, TableSessionSchema } from '../dinein/schemas';
import { Table, TableSchema } from '../dinein/schemas/table.schema';

import { GeoModule } from '../geo/geo.module';
import { BenefitsModule } from '../benefits/benefits.module';
import { Cart, CartSchema } from '../carts/schemas';
import { Promotion, PromotionSchema, Voucher, VoucherSchema } from '../promotions/schemas';
import { DeliveryCheckoutService } from './services/delivery-checkout.service';
import { DineInCheckoutService } from './services/dinein-checkout.service';
import { VnpayService } from './services/vnpay.service';
import { CheckoutPaymentService } from './services/checkout-payment.service';
import { MomoService } from './services/momo.service';
import { CheckoutPaymentController } from './controllers/checkout-payment.controller';
import { SystemConfigsModule } from '../system-config/system-configs.module';
import { RealtimeModule } from '../realtime/realtime.module';
import { OrderLifecycleService } from './services/order-lifecycle.service';
import { OrderTrackingQueryService } from './services/order-tracking-query.service';
import { DriverOrdersController } from './controllers/driver-orders.controller';
import { CustomerOrdersController } from './controllers/customer-orders.controller';
import { SettlementService } from './services/settlement.service';
import { MerchantOrdersController } from './controllers/merchant-orders.controller';
import { DriversModule } from '../drivers/drivers.module';
import { NotificationsModule } from '../notifications/notifications.module';
import { DriverProfile, DriverProfileSchema } from '../drivers/schemas/driver-profile.schema';
import { User, UserSchema } from '../users/schemas/user.schema';
import { MerchantOrderQueryService } from './services/merchant-order-query.service';
import { DriverOrderQueryService } from './services/driver-order-query.service';
import { DriverProofUploadService } from './services/driver-proof-upload.service';
import { CloudinaryModule } from 'src/common/services/cloudinary.module';
import { DriverEarningsController } from './controllers/driver-earnings.controller';
import { DriverEarningsQueryService } from './services/driver-earnings-query.service';
import { MerchantStatisticsController } from './controllers/merchant-statistics.controller';
import { MerchantStatisticsService } from './services/merchant-statistics.service';
import { CustomerOrderQueryService } from './services/customer-order-query.service';
import { Review, ReviewSchema } from '../reviews/schemas/review.schema';
import { DriverReview, DriverReviewSchema } from '../reviews/schemas/driver-review.schema';
import { MerchantReview, MerchantReviewSchema } from '../reviews/schemas/merchant-review.schema';
import { PublicDineInCheckoutController } from './controllers/public-dinein-checkout.controller';
import { DineInModule } from '../dinein/dine-in.module';

@Module({
    imports: [
        MongooseModule.forFeature([
            { name: Order.name, schema: OrderSchema },
            { name: Cart.name, schema: CartSchema },
            { name: Payment.name, schema: PaymentSchema },
            { name: Promotion.name, schema: PromotionSchema },
            { name: Voucher.name, schema: VoucherSchema },
            { name: Merchant.name, schema: MerchantSchema },
            { name: Product.name, schema: ProductSchema },
            { name: TableSession.name, schema: TableSessionSchema },
            { name: Table.name, schema: TableSchema },

            // thêm
            { name: DriverProfile.name, schema: DriverProfileSchema },
            { name: User.name, schema: UserSchema },
            { name: Review.name, schema: ReviewSchema },
            { name: MerchantReview.name, schema: MerchantReviewSchema },
            { name: DriverReview.name, schema: DriverReviewSchema },
        ]),
        GeoModule,
        BenefitsModule,
        SystemConfigsModule,
        CloudinaryModule,
        RealtimeModule,
        DriversModule,
        DineInModule,
        NotificationsModule,
    ],
    controllers: [
        DeliveryCheckoutController,
        DineInCheckoutController,
        CheckoutPaymentController,
        DriverEarningsController,
        CustomerOrdersController,
        MerchantOrdersController,
        DriverOrdersController,
        MerchantStatisticsController,
        CustomerOrdersController,
        PublicDineInCheckoutController
    ],
    providers: [
        DeliveryCheckoutService,
        DineInCheckoutService,
        CheckoutPricingService,
        PromotionEngineService,
        DriverEarningsQueryService,
        DriverOrderQueryService,
        OrderFactoryService,
        VnpayService,
        MomoService,
        CheckoutPaymentService,
        OrderLifecycleService,
        OrderTrackingQueryService,
        SettlementService,
        MerchantOrderQueryService,
        DriverProofUploadService,
        MerchantStatisticsService,

        CustomerOrderQueryService
    ],
    exports: [OrderLifecycleService],
})
export class OrdersModule { }
