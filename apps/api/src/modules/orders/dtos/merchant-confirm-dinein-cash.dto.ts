import { Type } from 'class-transformer';
import { IsNumber, IsOptional, IsString, Min } from 'class-validator';

export class MerchantConfirmDineInCashDto {
    @Type(() => Number)
    @IsNumber()
    @Min(0)
    received_amount: number;

    @IsOptional()
    @IsString()
    note?: string;
}
