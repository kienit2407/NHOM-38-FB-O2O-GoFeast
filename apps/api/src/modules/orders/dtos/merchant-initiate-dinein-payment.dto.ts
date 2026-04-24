import { IsIn, IsString } from 'class-validator';

export class MerchantInitiateDineInPaymentDto {
    @IsString()
    @IsIn(['vnpay', 'momo'])
    payment_method: 'vnpay' | 'momo';
}
