import {
    Body,
    Controller,
    Get,
    Param,
    Patch,
    Query,
    Req,
    UseGuards,
} from '@nestjs/common';
import { JwtAuthGuard } from 'src/modules/auth';
import { Roles } from 'src/modules/auth/decorators/roles.decorator';
import { RolesGuard } from 'src/modules/auth/guards/roles.guard';
import { ClientGuard } from 'src/modules/auth/guards/client.guard';
import { Client } from 'src/modules/auth/decorators/client.decorator';

import { MerchantOrderActionDto } from '../dtos/merchant-order-action.dto';
import { OrderLifecycleService } from '../services/order-lifecycle.service';
import { MerchantOrderQueryService } from '../services/merchant-order-query.service';
import { MerchantOrdersQueryDto } from '../dtos/merchant-orders.query.dto';
import { MerchantRejectOrderDto } from '../dtos/merchant-reject-order.dto';
import { CheckoutPaymentService } from '../services/checkout-payment.service';
import { MerchantInitiateDineInPaymentDto } from '../dtos/merchant-initiate-dinein-payment.dto';
import { MerchantConfirmDineInCashDto } from '../dtos/merchant-confirm-dinein-cash.dto';

@Controller('merchant/orders')
@Client('merchant_web')
@UseGuards(JwtAuthGuard, RolesGuard, ClientGuard)
@Roles('merchant')
export class MerchantOrdersController {
    constructor(
        private readonly lifecycle: OrderLifecycleService,
        private readonly queryService: MerchantOrderQueryService,
        private readonly checkoutPaymentService: CheckoutPaymentService,
    ) { }

    @Get()
    async list(@Req() req: any, @Query() query: MerchantOrdersQueryDto) {
        const data = await this.queryService.listForMerchantOwner(req.user.userId, query);
        return { success: true, data };
    }

    @Get(':id')
    async detail(@Req() req: any, @Param('id') id: string) {
        const data = await this.queryService.getDetailForMerchantOwner(
            req.user.userId,
            id,
        );
        return { success: true, data };
    }

    @Patch(':id/confirm')
    async confirm(
        @Req() req: any,
        @Param('id') id: string,
        @Body() dto: MerchantOrderActionDto,
    ) {
        await this.lifecycle.merchantConfirmOrder(req.user.userId, id, dto.note);

        const data = await this.queryService.getDetailForMerchantOwner(
            req.user.userId,
            id,
        );

        return { success: true, data };
    }

    @Patch(':id/reject')
    async reject(
        @Req() req: any,
        @Param('id') id: string,
        @Body() dto: MerchantRejectOrderDto,
    ) {
        await this.lifecycle.merchantRejectPendingOrder(
            req.user.userId,
            id,
            dto.reason,
        );

        const data = await this.queryService.getDetailForMerchantOwner(
            req.user.userId,
            id,
        );

        return { success: true, data };
    }

    @Patch(':id/preparing')
    async preparing(
        @Req() req: any,
        @Param('id') id: string,
        @Body() dto: MerchantOrderActionDto,
    ) {
        await this.lifecycle.merchantStartPreparing(req.user.userId, id, dto.note);

        const data = await this.queryService.getDetailForMerchantOwner(
            req.user.userId,
            id,
        );

        return { success: true, data };
    }

    @Patch(':id/ready-for-pickup')
    async ready(
        @Req() req: any,
        @Param('id') id: string,
        @Body() dto: MerchantOrderActionDto,
    ) {
        await this.lifecycle.merchantReadyForPickup(req.user.userId, id, dto.note);

        const data = await this.queryService.getDetailForMerchantOwner(
            req.user.userId,
            id,
        );

        return { success: true, data };
    }

    @Patch(':id/dispatch/retry')
    async retryDispatch(
        @Req() req: any,
        @Param('id') id: string,
        @Body() dto: MerchantOrderActionDto,
    ) {
        await this.lifecycle.merchantRetryDispatch(id, req.user.userId, dto.note);

        const data = await this.queryService.getDetailForMerchantOwner(
            req.user.userId,
            id,
        );

        return { success: true, data };
    }

    @Patch(':id/payments/initiate')
    async initiateDineInPayment(
        @Req() req: any,
        @Param('id') id: string,
        @Body() dto: MerchantInitiateDineInPaymentDto,
    ) {
        const payment = await this.checkoutPaymentService.merchantInitiateDineInPayment(
            {
                merchantUserId: req.user.userId,
                orderId: id,
                paymentMethod: dto.payment_method,
                clientIp:
                    req.headers?.['x-forwarded-for']?.toString()?.split(',')?.[0]?.trim() ??
                    req.ip ??
                    null,
            },
        );

        const order = await this.queryService.getDetailForMerchantOwner(
            req.user.userId,
            id,
        );

        return {
            success: true,
            data: {
                order,
                payment: payment.payment,
                payment_action: payment.payment_action,
                already_paid: payment.already_paid,
            },
        };
    }

    @Patch(':id/payments/cash/confirm')
    async confirmDineInCashPayment(
        @Req() req: any,
        @Param('id') id: string,
        @Body() dto: MerchantConfirmDineInCashDto,
    ) {
        const result = await this.checkoutPaymentService.merchantConfirmDineInCashPayment(
            {
                merchantUserId: req.user.userId,
                orderId: id,
                receivedAmount: Number(dto.received_amount ?? 0),
                note: dto.note,
            },
        );

        const order = await this.queryService.getDetailForMerchantOwner(
            req.user.userId,
            id,
        );

        return {
            success: true,
            data: {
                order,
                payment: result.payment,
                received_amount: result.received_amount,
                change_amount: result.change_amount,
            },
        };
    }
}
