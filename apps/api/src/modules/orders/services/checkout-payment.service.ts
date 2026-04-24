import {
    BadRequestException,
    Injectable,
    NotFoundException,
} from '@nestjs/common';
import { InjectModel } from '@nestjs/mongoose';
import { Model, Types } from 'mongoose';
import { ConfigService } from 'src/config/config.service';
import { randomUUID } from 'crypto';

import {
    Order,
    OrderDocument,
    PaymentMethod as OrderPaymentMethod,
    PaymentStatus as OrderPaymentStatus,
    OrderType,
} from '../schemas/order.schema';
import {
    Payment,
    PaymentDocument,
    PaymentMethod,
    PaymentStatus,
} from 'src/modules/payments/schemas/payment.schema';

import { OrderFactoryService } from './order-factory.service';
import { VnpayService } from './vnpay.service';
import { MomoService } from './momo.service';
import { OrderLifecycleService } from './order-lifecycle.service';
import {
    Merchant,
    MerchantDocument,
} from 'src/modules/merchants/schemas/merchant.schema';

@Injectable()
export class CheckoutPaymentService {
    constructor(
        @InjectModel(Order.name)
        private readonly orderModel: Model<OrderDocument>,
        @InjectModel(Payment.name)
        private readonly paymentModel: Model<PaymentDocument>,
        @InjectModel(Merchant.name)
        private readonly merchantModel: Model<MerchantDocument>,
        private readonly orderFactory: OrderFactoryService,
        private readonly vnpay: VnpayService,
        private readonly momo: MomoService,
        private readonly config: ConfigService,
        private readonly orderLifecycleService: OrderLifecycleService,
    ) { }

    private get frontendResultUrl() {
        return (
            this.config.get<string>('FRONTEND_PAYMENT_RESULT_URL') ||
            'http://localhost:5173/payment-result'
        );
    }

    private oid(id: string, name = 'id') {
        if (!Types.ObjectId.isValid(id)) throw new Error(`Invalid ${name}`);
        return new Types.ObjectId(id);
    }

    private buildFrontendRedirect(params: Record<string, string | number | null>) {
        const url = new URL(this.frontendResultUrl);
        for (const [k, v] of Object.entries(params)) {
            if (v === null || v === undefined) continue;
            url.searchParams.set(k, String(v));
        }
        return url.toString();
    }

    private mapPayment(payment: any) {
        if (!payment) return null;

        return {
            payment_id: String(payment._id),
            status: payment.status,
            method: payment.payment_method,
            amount: Number(payment.amount ?? 0),
        };
    }

    private async assertMerchantOwnsOrder(args: {
        merchantUserId: string;
        order: any;
    }) {
        const merchant = await this.merchantModel.findOne({
            _id: args.order.merchant_id,
            owner_user_id: this.oid(args.merchantUserId, 'merchantUserId'),
            deleted_at: null,
        });

        if (!merchant) {
            throw new NotFoundException('Merchant not found');
        }

        return merchant;
    }

    async createPaymentAction(args: {
        order: any;
        payment: any;
        clientIp?: string | null;
    }): Promise<
        | null
        | {
            type: 'redirect_url';
            url: string;
        }
    > {
        if (!args.payment) return null;

        if (args.payment.payment_method === PaymentMethod.VNPAY) {
            const txnRef = String(args.payment._id);

            const r = this.vnpay.createPaymentUrl({
                orderNumber: args.order.order_number,
                amount: Number(args.payment.amount),
                txnRef,
                clientIp: args.clientIp ?? '127.0.0.1',
            });

            args.payment.gateway_response = {
                ...(args.payment.gateway_response ?? {}),
                vnpay: {
                    txn_ref: txnRef,
                    payment_url: r.paymentUrl,
                    init_params: r.params,
                },
            };
            await args.payment.save();

            return {
                type: 'redirect_url',
                url: r.paymentUrl,
            };
        }

        if (args.payment.payment_method === PaymentMethod.MOMO) {
            const r = await this.momo.createPaymentUrl({
                orderId: String(args.order.order_number),
                amount: Number(args.payment.amount),
                orderInfo: `Thanh toan don hang ${args.order.order_number}`,
                extraData: {
                    payment_id: String(args.payment._id),
                    order_id: String(args.order._id),
                },
            });

            args.payment.gateway_response = {
                ...(args.payment.gateway_response ?? {}),
                momo: {
                    request_id: r.requestId,
                    order_id: r.orderId,
                    pay_url: r.payUrl,
                    short_link: r.shortLink,
                    init_response: r.raw,
                },
            };
            await args.payment.save();

            return {
                type: 'redirect_url',
                url: r.payUrl,
            };
        }

        return null;
    }

    async merchantInitiateDineInPayment(args: {
        merchantUserId: string;
        orderId: string;
        paymentMethod: 'vnpay' | 'momo';
        clientIp?: string | null;
    }) {
        const order = await this.orderModel.findById(this.oid(args.orderId, 'orderId'));
        if (!order) {
            throw new NotFoundException('Order not found');
        }

        await this.assertMerchantOwnsOrder({
            merchantUserId: args.merchantUserId,
            order,
        });

        if (order.order_type !== OrderType.DINE_IN) {
            throw new BadRequestException('Only dine-in order supports merchant payment settlement');
        }

        if (order.status === 'cancelled') {
            throw new BadRequestException('Cancelled order cannot be settled');
        }

        if (order.status === 'completed') {
            throw new BadRequestException('Completed order cannot be settled again');
        }

        if (order.payment_status === OrderPaymentStatus.PAID) {
            return {
                already_paid: true,
                payment: this.mapPayment(
                    await this.paymentModel
                        .findOne({
                            order_id: order._id,
                            status: PaymentStatus.SUCCESS,
                        })
                        .sort({ created_at: -1 }),
                ),
                payment_action: null,
            };
        }

        const targetMethod =
            args.paymentMethod === 'momo' ? PaymentMethod.MOMO : PaymentMethod.VNPAY;

        const payerUserId = order.customer_id
            ? new Types.ObjectId(String(order.customer_id))
            : this.oid(args.merchantUserId, 'merchantUserId');

        await this.paymentModel.updateMany(
            {
                order_id: order._id,
                status: PaymentStatus.PENDING,
                payment_method: { $ne: targetMethod },
            },
            {
                $set: {
                    status: PaymentStatus.FAILED,
                    gateway_response: {
                        by_merchant_switch_method_at: new Date().toISOString(),
                    },
                },
            },
        );

        let payment = await this.paymentModel
            .findOne({
                order_id: order._id,
                payment_method: targetMethod,
                status: PaymentStatus.PENDING,
            })
            .sort({ created_at: -1 });

        if (!payment) {
            payment = await this.paymentModel.create({
                order_id: order._id,
                user_id: payerUserId,
                payment_method: targetMethod,
                amount: Number(order.total_amount ?? 0),
                currency: 'VND',
                idempotency_key: randomUUID(),
                status: PaymentStatus.PENDING,
                gateway_response: {
                    source: 'merchant_dine_in_settlement',
                },
            });
        }

        const paymentAction = await this.createPaymentAction({
            order,
            payment,
            clientIp: args.clientIp ?? null,
        });

        order.payment_method = targetMethod as any;
        order.payment_status = OrderPaymentStatus.PENDING;
        await order.save();

        return {
            already_paid: false,
            payment: this.mapPayment(payment),
            payment_action: paymentAction,
        };
    }

    async merchantConfirmDineInCashPayment(args: {
        merchantUserId: string;
        orderId: string;
        receivedAmount: number;
        note?: string;
    }) {
        const order = await this.orderModel.findById(this.oid(args.orderId, 'orderId'));
        if (!order) {
            throw new NotFoundException('Order not found');
        }

        await this.assertMerchantOwnsOrder({
            merchantUserId: args.merchantUserId,
            order,
        });

        if (order.order_type !== OrderType.DINE_IN) {
            throw new BadRequestException('Only dine-in order supports merchant payment settlement');
        }

        if (order.status === 'cancelled') {
            throw new BadRequestException('Cancelled order cannot be settled');
        }

        if (order.status === 'completed') {
            throw new BadRequestException('Completed order cannot be settled again');
        }

        const totalAmount = Number(order.total_amount ?? 0);
        const receivedAmount = Number(args.receivedAmount ?? 0);
        const changeAmount = receivedAmount - totalAmount;

        if (!Number.isFinite(receivedAmount) || receivedAmount < totalAmount) {
            throw new BadRequestException('Received amount must be greater than or equal total amount');
        }

        if (order.payment_status === OrderPaymentStatus.PAID) {
            if (order.payment_method !== OrderPaymentMethod.CASH) {
                throw new BadRequestException('Order already paid by online method');
            }

            await this.orderLifecycleService.completeDineInOrderAfterPayment(
                String(order._id),
                {
                    changedBy: args.merchantUserId,
                    note: args.note ?? 'Merchant confirmed paid dine-in order',
                },
            );

            const paidPayment = await this.paymentModel
                .findOne({
                    order_id: order._id,
                    status: PaymentStatus.SUCCESS,
                })
                .sort({ created_at: -1 });

            return {
                payment: this.mapPayment(paidPayment),
                received_amount: receivedAmount,
                change_amount: changeAmount,
            };
        }

        await this.paymentModel.updateMany(
            {
                order_id: order._id,
                status: PaymentStatus.PENDING,
            },
            {
                $set: {
                    status: PaymentStatus.FAILED,
                    gateway_response: {
                        cancelled_by_cash_settlement_at: new Date().toISOString(),
                    },
                },
            },
        );

        const payerUserId = order.customer_id
            ? new Types.ObjectId(String(order.customer_id))
            : this.oid(args.merchantUserId, 'merchantUserId');

        const payment = await this.paymentModel.create({
            order_id: order._id,
            user_id: payerUserId,
            payment_method: PaymentMethod.CASH,
            amount: totalAmount,
            currency: 'VND',
            idempotency_key: randomUUID(),
            status: PaymentStatus.SUCCESS,
            completed_at: new Date(),
            gateway_response: {
                source: 'merchant_dine_in_cash_settlement',
                cash: {
                    received_amount: receivedAmount,
                    change_amount: changeAmount,
                    confirmed_by: args.merchantUserId,
                    confirmed_at: new Date().toISOString(),
                },
            },
        });

        order.payment_method = OrderPaymentMethod.CASH;
        order.payment_status = OrderPaymentStatus.PAID;
        order.paid_at = order.paid_at ?? new Date();
        await order.save();

        await this.orderLifecycleService.completeDineInOrderAfterPayment(
            String(order._id),
            {
                changedBy: args.merchantUserId,
                note:
                    args.note ??
                    `Thanh toán tiền mặt. Khách đưa ${receivedAmount}, tiền thối ${changeAmount}`,
            },
        );

        return {
            payment: this.mapPayment(payment),
            received_amount: receivedAmount,
            change_amount: changeAmount,
        };
    }

    private async finalizeSuccess(args: {
        payment: any;
        order: any;
        gatewayTransactionId?: string | null;
        raw: any;
    }) {
        const alreadySucceeded = args.payment.status === PaymentStatus.SUCCESS;
        const source = String(args.payment.gateway_response?.source ?? '');

        args.payment.status = PaymentStatus.SUCCESS;
        args.payment.completed_at = args.payment.completed_at ?? new Date();
        if (args.gatewayTransactionId) {
            args.payment.gateway_transaction_id = args.gatewayTransactionId;
        }
        args.payment.gateway_response = {
            ...(args.payment.gateway_response ?? {}),
            last_success_callback: args.raw,
        };
        await args.payment.save();

        args.order.payment_status = OrderPaymentStatus.PAID;
        args.order.paid_at = args.order.paid_at ?? new Date();
        await args.order.save();

        if (!alreadySucceeded) {
            const snap = args.payment.gateway_response?.checkout_benefits ?? {
                auto_applied: [],
                voucher_applied: null,
            };

            if (args.order.customer_id) {
                await this.orderFactory.markBenefitsUsed({
                    userId: String(args.order.customer_id),
                    orderId: String(args.order._id),
                    promotions: {
                        auto_applied: snap.auto_applied ?? [],
                        voucher_applied: snap.voucher_applied ?? null,
                    },
                });
            }

            await this.orderFactory.clearCartByOrder(args.order);

            if (args.order.order_type === OrderType.DELIVERY) {
                await this.orderLifecycleService.activateDeliveryOrder(
                    String(args.order._id),
                );
            } else if (
                args.order.order_type === OrderType.DINE_IN &&
                source !== 'merchant_dine_in_settlement'
            ) {
                await this.orderLifecycleService.activateDineInOrder(
                    String(args.order._id),
                );
            }
        }

        if (
            args.order.order_type === OrderType.DINE_IN &&
            source === 'merchant_dine_in_settlement'
        ) {
            try {
                await this.orderLifecycleService.completeDineInOrderAfterPayment(
                    String(args.order._id),
                    {
                        note: 'Đồng bộ trạng thái thanh toán online',
                    },
                );
            } catch (_) {
                // giữ callback idempotent, không throw ngược về gateway
            }
        }
    }

    private async finalizeFailed(args: {
        payment: any;
        order: any;
        raw: any;
    }) {
        if (args.payment.status === PaymentStatus.SUCCESS) {
            return;
        }

        args.payment.status = PaymentStatus.FAILED;
        args.payment.gateway_response = {
            ...(args.payment.gateway_response ?? {}),
            last_failed_callback: args.raw,
        };
        await args.payment.save();

        args.order.payment_status = OrderPaymentStatus.FAILED;
        await args.order.save();
    }

    async handleVnpReturn(rawQuery: Record<string, any>) {
        const verify = this.vnpay.verifyReturn(rawQuery);

        if (!verify.ok) {
            return {
                redirectUrl: this.buildFrontendRedirect({
                    gateway: 'vnpay',
                    status: 'error',
                    message: 'Invalid VNPAY signature',
                }),
            };
        }

        const payment = await this.paymentModel.findOne({
            'gateway_response.vnpay.txn_ref': verify.txnRef,
        });

        if (!payment) {
            return {
                redirectUrl: this.buildFrontendRedirect({
                    gateway: 'vnpay',
                    status: 'error',
                    message: 'Payment not found',
                }),
            };
        }

        const order = await this.orderModel.findById(payment.order_id);
        if (!order) {
            return {
                redirectUrl: this.buildFrontendRedirect({
                    gateway: 'vnpay',
                    status: 'error',
                    message: 'Order not found',
                }),
            };
        }

        if (verify.responseCode === '00') {
            await this.finalizeSuccess({
                payment,
                order,
                gatewayTransactionId: verify.transactionNo,
                raw: rawQuery,
            });

            return {
                redirectUrl: this.buildFrontendRedirect({
                    gateway: 'vnpay',
                    status: 'success',
                    order_id: String(order._id),
                    order_number: order.order_number,
                    code: verify.responseCode,
                }),
            };
        }

        await this.finalizeFailed({
            payment,
            order,
            raw: rawQuery,
        });

        return {
            redirectUrl: this.buildFrontendRedirect({
                gateway: 'vnpay',
                status: 'failed',
                order_id: String(order._id),
                order_number: order.order_number,
                code: verify.responseCode,
            }),
        };
    }

    async handleVnpIpn(rawQuery: Record<string, any>) {
        const verify = this.vnpay.verifyReturn(rawQuery);

        if (!verify.ok) {
            return { RspCode: '97', Message: 'Invalid signature' };
        }

        const payment = await this.paymentModel.findOne({
            'gateway_response.vnpay.txn_ref': verify.txnRef,
        });

        if (!payment) {
            return { RspCode: '01', Message: 'Payment not found' };
        }

        const order = await this.orderModel.findById(payment.order_id);
        if (!order) {
            return { RspCode: '01', Message: 'Order not found' };
        }

        if (verify.responseCode === '00') {
            await this.finalizeSuccess({
                payment,
                order,
                gatewayTransactionId: verify.transactionNo,
                raw: rawQuery,
            });
            return { RspCode: '00', Message: 'Confirm Success' };
        }

        await this.finalizeFailed({
            payment,
            order,
            raw: rawQuery,
        });

        return { RspCode: '00', Message: 'Confirm Success' };
    }

    async handleMomoReturn(rawQuery: Record<string, any>) {
        const orderNumber = String(rawQuery.orderId || '');
        const order = await this.orderModel.findOne({ order_number: orderNumber });

        if (!order) {
            return {
                redirectUrl: this.buildFrontendRedirect({
                    gateway: 'momo',
                    status: 'error',
                    message: 'Order not found',
                }),
            };
        }

        const payment = await this.paymentModel.findOne({
            order_id: order._id,
            payment_method: PaymentMethod.MOMO,
        });

        if (!payment) {
            return {
                redirectUrl: this.buildFrontendRedirect({
                    gateway: 'momo',
                    status: 'error',
                    message: 'Payment not found',
                }),
            };
        }

        const resultCode = Number(rawQuery.resultCode ?? -1);

        if (resultCode === 0 || resultCode === 9000) {
            await this.finalizeSuccess({
                payment,
                order,
                gatewayTransactionId: rawQuery.transId ? String(rawQuery.transId) : null,
                raw: rawQuery,
            });

            return {
                redirectUrl: this.buildFrontendRedirect({
                    gateway: 'momo',
                    status: 'success',
                    order_id: String(order._id),
                    order_number: order.order_number,
                    code: resultCode,
                }),
            };
        }

        await this.finalizeFailed({
            payment,
            order,
            raw: rawQuery,
        });

        return {
            redirectUrl: this.buildFrontendRedirect({
                gateway: 'momo',
                status: 'failed',
                order_id: String(order._id),
                order_number: order.order_number,
                code: resultCode,
            }),
        };
    }

    async handleMomoIpn(body: Record<string, any>) {
        const verify = this.momo.verifyIpn(body);

        if (!verify.ok) {
            return;
        }

        const orderNumber = String(body.orderId || '');
        const order = await this.orderModel.findOne({ order_number: orderNumber });
        if (!order) return;

        const payment = await this.paymentModel.findOne({
            order_id: order._id,
            payment_method: PaymentMethod.MOMO,
        });
        if (!payment) return;

        const resultCode = Number(body.resultCode ?? -1);

        if (resultCode === 0 || resultCode === 9000) {
            await this.finalizeSuccess({
                payment,
                order,
                gatewayTransactionId: body.transId ? String(body.transId) : null,
                raw: body,
            });
            return;
        }

        await this.finalizeFailed({
            payment,
            order,
            raw: body,
        });
    }
}
