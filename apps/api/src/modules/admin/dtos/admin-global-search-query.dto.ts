import { IsNumberString, IsOptional, IsString, MaxLength } from 'class-validator';

export class AdminGlobalSearchQueryDto {
    @IsString()
    @MaxLength(100)
    q: string;

    @IsOptional()
    @IsNumberString()
    limit?: string = '5';
}
