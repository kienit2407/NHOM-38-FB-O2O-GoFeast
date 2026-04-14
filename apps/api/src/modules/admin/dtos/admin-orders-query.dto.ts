import { IsEnum, IsNumberString, IsOptional, IsString, MaxLength } from 'class-validator';
import { OrderType } from 'src/modules/orders/schemas/order.schema';

export class AdminOrdersQueryDto {
    @IsOptional()
    @IsEnum(OrderType)
    order_type?: OrderType;

    @IsOptional()
    @IsString()
    @MaxLength(100)
    q?: string;

    @IsOptional()
    @IsString()
    @MaxLength(50)
    status?: string;

    @IsOptional()
    @IsNumberString()
    page?: string = '1';

    @IsOptional()
    @IsNumberString()
    limit?: string = '20';
}
