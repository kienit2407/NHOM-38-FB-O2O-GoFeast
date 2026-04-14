import { IsNumberString, IsOptional } from 'class-validator';

export class AdminDashboardQueryDto {
    @IsOptional()
    @IsNumberString()
    heatmap_hours?: string = '6';
}
