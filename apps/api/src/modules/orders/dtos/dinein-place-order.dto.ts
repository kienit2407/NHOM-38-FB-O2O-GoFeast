import { IsEnum, IsMongoId, IsOptional, IsString } from 'class-validator';
import { PaymentMethod } from '../schemas/order.schema';

export class DineInPlaceOrderDto {
    @IsMongoId()
    table_session_id: string;

    @IsOptional()
    @IsEnum(PaymentMethod)
    payment_method?: PaymentMethod;

    @IsOptional()
    @IsString()
    voucher_code?: string;

    @IsOptional()
    @IsString()
    order_note?: string;
}
