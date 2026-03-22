import {
    Body,
    Controller,
    Get,
    HttpCode,
    HttpStatus,
    Patch,
    Post,
    Req,
    UseGuards,
} from '@nestjs/common';
import { Client } from 'src/modules/auth/decorators/client.decorator';
import { Roles } from 'src/modules/auth/decorators/roles.decorator';
import { ClientGuard } from 'src/modules/auth/guards/client.guard';
import { JwtAuthGuard } from 'src/modules/auth/guards/jwt-auth.guard';
import { RolesGuard } from 'src/modules/auth/guards/roles.guard';
import { DriverProfilesService } from '../services/driver-profiles.service';
import { UpdateDriverAvailabilityDto } from '../dtos/update-driver-availability.dto';
import { UpdateDriverLocationDto } from '../dtos/update-driver-location.dto';
import { UpdateDriverProfileDto } from '../dtos/update-driver-profile.dto';


@Controller('drivers')
@Client('driver_mobile')
@UseGuards(JwtAuthGuard, RolesGuard, ClientGuard)
@Roles('driver')
export class DriversController {
    constructor(
        private readonly driverProfilesService: DriverProfilesService,
    ) { }
    @Get('me/profile')
    async getMyProfile(@Req() req: any) {
        const data = await this.driverProfilesService.getMyProfile(req.user.userId);
        return { success: true, data };
    }

    @Patch('me/profile')
    @HttpCode(HttpStatus.OK)
    async updateMyProfile(
        @Req() req: any,
        @Body() dto: UpdateDriverProfileDto,
    ) {
        const data = await this.driverProfilesService.updateMyProfile(
            req.user.userId,
            dto,
        );
        return { success: true, data };
    }
    @Get('me/live-state')
    async getMyLiveState(@Req() req: any) {
        const data = await this.driverProfilesService.getLiveState(req.user.userId);
        return { success: true, data };
    }

    @Patch('me/availability')
    @HttpCode(HttpStatus.OK)
    async setAvailability(
        @Req() req: any,
        @Body() dto: UpdateDriverAvailabilityDto,
    ) {
        const data = await this.driverProfilesService.setAvailability(
            req.user.userId,
            dto.acceptFoodOrders,
        );

        return {
            success: true,
            data: {
                accept_food_orders: data?.accept_food_orders ?? false,
                verification_status: data?.verification_status ?? null,
                updated_at: data?.updated_at ?? null,
            },
        };
    }

    @Post('me/location')
    @HttpCode(HttpStatus.OK)
    async updateMyLocation(
        @Req() req: any,
        @Body() dto: UpdateDriverLocationDto,
    ) {
        const data = await this.driverProfilesService.updateCurrentLocation({
            userId: req.user.userId,
            lat: dto.lat,
            lng: dto.lng,
        });

        return {
            success: true,
            data: {
                current_location: data?.current_location ?? null,
                last_location_update: data?.last_location_update ?? null,
            },
        };
    }
}