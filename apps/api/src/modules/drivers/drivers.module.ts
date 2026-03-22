import { Module } from '@nestjs/common';
import { MongooseModule } from '@nestjs/mongoose';

import {
    DriverProfile,
    DriverProfileSchema,
} from './schemas/driver-profile.schema';
import { DriversController } from './controllers/drivers.controller';
import { DriverProfilesService } from './services/driver-profiles.service';
import { DriverLocationRelayService } from './services/driver-location-relay.service';

import { Order, OrderSchema } from 'src/modules/orders/schemas/order.schema';
import { RealtimeModule } from 'src/modules/realtime/realtime.module';
import { GeoModule } from 'src/modules/geo/geo.module';
import { User, UserSchema } from '../users/schemas/user.schema';

@Module({
    imports: [
        MongooseModule.forFeature([
            { name: DriverProfile.name, schema: DriverProfileSchema },
            { name: Order.name, schema: OrderSchema },
            { name: User.name, schema: UserSchema },
        ]),
        RealtimeModule,
        GeoModule,
    ],
    controllers: [DriversController],
    providers: [DriverProfilesService, DriverLocationRelayService],
    exports: [DriverProfilesService],
})
export class DriversModule { }