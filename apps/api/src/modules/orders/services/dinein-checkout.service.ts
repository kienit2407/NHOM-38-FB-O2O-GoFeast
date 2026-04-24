import { BadRequestException, Injectable, NotFoundException } from '@nestjs/common';
import { InjectModel } from '@nestjs/mongoose';
import { Model, Types } from 'mongoose';

import { Merchant, MerchantDocument } from 'src/modules/merchants/schemas/merchant.schema';
import { TableSession, TableSessionDocument } from 'src/modules/dinein/schemas';

import { Order, OrderDocument, OrderType, PaymentMethod } from '../schemas/order.schema';
import { DineInCheckoutPreviewQueryDto } from '../dtos/dinein-checkout-preview.query.dto';
import { DineInPlaceOrderDto } from '../dtos/dinein-place-order.dto';
import { CheckoutPricingService } from './checkout-pricing.service';
import { PromotionEngineService } from './promotion-engine.service';
import { OrderFactoryService } from './order-factory.service';
import { Cart, CartDocument, CartStatus } from 'src/modules/carts/schemas';
import { CheckoutPaymentService } from './checkout-payment.service';
import { OrderLifecycleService } from './order-lifecycle.service';

@Injectable()
export class DineInCheckoutService {
    constructor(
        @InjectModel(Cart.name)
        private readonly cartModel: Model<CartDocument>,

        @InjectModel(Merchant.name)
        private readonly merchantModel: Model<MerchantDocument>,

        //  1. Sửa lại cho đúng: @InjectModel(TableSession.name) đi kèm với tableSessionModel
        @InjectModel(TableSession.name)
        private readonly tableSessionModel: Model<TableSessionDocument>,

        //  2. Thêm lại @InjectModel(Order.name) cho orderModel (mình thấy bạn đã thêm đúng rồi)
        @InjectModel(Order.name)
        private readonly orderModel: Model<OrderDocument>,

        //  3. Dịch chuyển checkoutPayment xuống dưới cùng với các Service khác (không dùng @InjectModel cho Service)
        private readonly checkoutPayment: CheckoutPaymentService,
        private readonly orderLifecycleService: OrderLifecycleService,
        private readonly pricingService: CheckoutPricingService,
        private readonly promotionEngine: PromotionEngineService,
        private readonly orderFactory: OrderFactoryService,
    ) { }

    private oid(id: string, name = 'id') {
        if (!Types.ObjectId.isValid(id)) {
            throw new BadRequestException(`Invalid ${name}`);
        }
        return new Types.ObjectId(id);
    }

    private async getTableSession(tableSessionId: string) {
        const session: any = await this.tableSessionModel.findById(
            this.oid(tableSessionId, 'tableSessionId'),
        ).lean();

        if (!session) throw new NotFoundException('TableSession not found');
        if (String(session.status ?? '').toLowerCase() !== 'active') {
            throw new BadRequestException('TableSession is not active');
        }

        return session;
    }

    private async getMerchant(merchantId: string) {
        const merchant: any = await this.merchantModel.findById(
            this.oid(merchantId, 'merchantId'),
        ).lean();

        if (!merchant) throw new NotFoundException('Merchant not found');
        if (merchant.is_accepting_orders === false) {
            throw new BadRequestException('Merchant is not accepting orders');
        }

        return merchant;
    }

    private async getActiveDineInCart(tableSessionId: string, merchantId: string) {
        const cart = await this.cartModel.findOne({
            table_session_id: this.oid(tableSessionId, 'tableSessionId'),
            merchant_id: this.oid(merchantId, 'merchantId'),
            order_type: OrderType.DINE_IN,
            status: CartStatus.ACTIVE,
            deleted_at: null,
        });

        if (!cart) throw new NotFoundException('Active dine-in cart not found');
        if (!cart.items?.length) throw new BadRequestException('Cart is empty');

        return cart;
    }

    async preview(userId: string | null, q: DineInCheckoutPreviewQueryDto) {
        const paymentMethod = PaymentMethod.CASH;
        const session: any = await this.getTableSession(q.table_session_id);
        const merchant: any = await this.getMerchant(String(session.merchant_id));
        const cart = await this.getActiveDineInCart(q.table_session_id, String(session.merchant_id));

        const subtotalBeforeDiscount = (cart.items ?? []).reduce(
            (s: number, it: any) => s + Number(it.item_total ?? 0),
            0,
        );

        const promotions = await this.promotionEngine.resolve({
            userId,
            merchantId: String(session.merchant_id),
            orderType: OrderType.DINE_IN,
            paymentMethod,
            subtotal_before_discount: subtotalBeforeDiscount,
            delivery_fee_before_discount: 0,
            cartItems: cart.items ?? [],
            voucherCode: q.voucher_code,
        });

        const platformFee = await this.pricingService.getPlatformFee(OrderType.DINE_IN);

        const pricing = this.pricingService.finalize({
            subtotal_before_discount: subtotalBeforeDiscount,
            delivery_fee_before_discount: 0,
            platform_fee: platformFee,
            raw_food_discount: promotions.raw_food_discount,
            raw_delivery_discount: 0,
        });

        const itemCount = (cart.items ?? []).reduce(
            (s: number, it: any) => s + Number(it.quantity ?? 0),
            0,
        );

        return {
            type: 'dine_in',
            merchant: {
                id: String(merchant._id),
                name: merchant.name,
                address: merchant.address ?? null,
            },
            dine_in: {
                table_session_id: String(session._id),
                table_id: session.table_id ? String(session.table_id) : null,
                estimated_prep_time_min: Number(merchant.average_prep_time_min ?? 15),
            },
            cart: {
                id: String(cart._id),
                item_count: itemCount,
                items: (cart.items ?? []).map((it: any) => ({
                    line_key: it.line_key,
                    item_type: it.item_type,
                    product_id: it.product_id ? String(it.product_id) : null,
                    topping_id: it.topping_id ? String(it.topping_id) : null,
                    name: it.product_name,
                    image_url: it.product_image_url ?? null,
                    quantity: Number(it.quantity ?? 0),
                    unit_price: Number(it.unit_price ?? 0),
                    base_price: it.base_price != null ? Number(it.base_price) : null,
                    item_total: Number(it.item_total ?? 0),
                    note: it.note ?? '',
                    selected_options: it.selected_options ?? [],
                    selected_toppings: it.selected_toppings ?? [],
                })),
            },
            payment: {
                selected_method: paymentMethod,
            },
            promotions,
            pricing,
        };
    }

    async placeOrder(
        userId: string | null,
        dto: DineInPlaceOrderDto,
        meta?: { clientIp?: string | null },
    ) {
        const session: any = await this.getTableSession(dto.table_session_id);
        const paymentMethod = PaymentMethod.CASH;

        const preview = await this.preview(userId, {
            table_session_id: dto.table_session_id,
            payment_method: paymentMethod,
            voucher_code: dto.voucher_code,
        });

        const cart = await this.getActiveDineInCart(
            dto.table_session_id,
            String(session.merchant_id),
        );

        const { order, payment } = await this.orderFactory.createDineInOrder({
            userId,
            merchantId: String(session.merchant_id),
            tableSessionId: dto.table_session_id,
            cart,
            dto: {
                order_note: dto.order_note,
                payment_method: paymentMethod,
            },
            preview,
        });

        let paymentAction: any = null;

        if (payment) {
            paymentAction = await this.checkoutPayment.createPaymentAction({
                order,
                payment,
                clientIp: meta?.clientIp ?? null,
            });
        } else {
            if (userId) {
                await this.orderFactory.markBenefitsUsed({
                    userId,
                    orderId: String(order._id),
                    promotions: preview.promotions,
                });
            }

            await this.orderFactory.clearCartByOrder(order);

            await this.orderLifecycleService.activateDineInOrder(String(order._id));
        }

        return {
            order_id: String(order._id),
            order_number: order.order_number,
            status: order.status,
            payment: payment
                ? {
                    payment_id: String(payment._id),
                    status: payment.status,
                    method: payment.payment_method,
                    amount: payment.amount,
                }
                : {
                    payment_id: null,
                    status: 'pending',
                    method: paymentMethod,
                    amount: preview.pricing.total_amount,
                },
            payment_action: paymentAction,
            pricing: preview.pricing,
            dine_in: preview.dine_in,
        };
    }
}
