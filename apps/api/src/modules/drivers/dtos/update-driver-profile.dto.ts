import { Transform } from 'class-transformer';
import {
    IsDateString,
    IsIn,
    IsOptional,
    IsString,
    MaxLength,
} from 'class-validator';

function trimOrUndefined(value: unknown) {
    if (value === undefined) return undefined;
    if (value === null) return null;
    if (typeof value !== 'string') return value;
    const v = value.trim();
    return v === '' ? null : v;
}

export class UpdateDriverProfileDto {
    @IsOptional()
    @Transform(({ value }) => trimOrUndefined(value))
    @IsString()
    @MaxLength(120)
    fullName?: string | null;

    @IsOptional()
    @Transform(({ value }) => trimOrUndefined(value))
    @IsString()
    @MaxLength(20)
    phone?: string | null;

    @IsOptional()
    @Transform(({ value }) => trimOrUndefined(value))
    @IsIn(['male', 'female', 'other'])
    gender?: 'male' | 'female' | 'other' | null;

    @IsOptional()
    @Transform(({ value }) => trimOrUndefined(value))
    @IsDateString()
    dateOfBirth?: string | null;

    @IsOptional()
    @Transform(({ value }) => trimOrUndefined(value))
    @IsString()
    @MaxLength(500)
    avatarUrl?: string | null;

    @IsOptional()
    @Transform(({ value }) => trimOrUndefined(value))
    @IsString()
    @MaxLength(120)
    bankName?: string | null;

    @IsOptional()
    @Transform(({ value }) => trimOrUndefined(value))
    @IsString()
    @MaxLength(120)
    bankAccountName?: string | null;

    @IsOptional()
    @Transform(({ value }) => trimOrUndefined(value))
    @IsString()
    @MaxLength(40)
    bankAccountNumber?: string | null;
}