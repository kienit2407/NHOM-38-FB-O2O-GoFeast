import {
    Body,
    Controller,
    Get,
    Post,
    Query,
    Req,
    UseGuards,
} from '@nestjs/common';
import express from 'express';

import { DineInSessionGuard } from 'src/modules/dinein/guards/dinein-session.guard';
import { CurrentDineIn } from 'src/modules/dinein/decorators/current-dinein.decorator';
import { OptionalJwtAuthGuard } from 'src/modules/auth/guards/optional-jwt-auth.guard';

import { DineInCheckoutPreviewQueryDto } from '../dtos/dinein-checkout-preview.query.dto';
import { DineInPlaceOrderDto } from '../dtos/dinein-place-order.dto';
import { DineInCheckoutService } from '../services/dinein-checkout.service';
import { PaymentMethod } from '../schemas/order.schema';

@Controller('checkout/dine-in/public')
@UseGuards(DineInSessionGuard, OptionalJwtAuthGuard)
export class PublicDineInCheckoutController {
    constructor(private readonly svc: DineInCheckoutService) { }

    private userId(user: any): string | null {
        const id = user?.sub ?? user?.userId ?? user?._id ?? user?.id;
        return id ? String(id) : null;
    }

    private getClientIp(req: express.Request) {
        const xff = req.headers['x-forwarded-for'];
        if (typeof xff === 'string' && xff.trim()) {
            return xff.split(',')[0].trim();
        }
        if (Array.isArray(xff) && xff.length) {
            return String(xff[0]).split(',')[0].trim();
        }
        return req.ip || req.socket?.remoteAddress || '127.0.0.1';
    }

    @Get('preview')
    async preview(
        @Req() req: any,
        @CurrentDineIn() dineIn: any,
        @Query() q: DineInCheckoutPreviewQueryDto,
    ) {
        const data = await this.svc.preview(this.userId(req.user), {
            table_session_id: dineIn.tableSessionId,
            payment_method: PaymentMethod.CASH,
            voucher_code: q.voucher_code,
        });

        return { success: true, data };
    }

    @Post('place-order')
    async placeOrder(
        @Req() req: express.Request & { user?: any },
        @CurrentDineIn() dineIn: any,
        @Body() dto: DineInPlaceOrderDto,
    ) {
        const data = await this.svc.placeOrder(
            this.userId((req as any).user),
            {
                table_session_id: dineIn.tableSessionId,
                voucher_code: dto.voucher_code,
                order_note: dto.order_note,
            },
            {
                clientIp: this.getClientIp(req),
            },
        );

        return { success: true, data };
    }
}
