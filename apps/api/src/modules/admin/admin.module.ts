import { Module } from '@nestjs/common';
import { MongooseModule } from '@nestjs/mongoose';

import { MerchantsModule } from '../merchants/merchants.module';
import { DriversModule } from '../drivers/drivers.module';
import { UsersModule } from '../users/users.module';
import { SystemConfigsModule } from '../system-config/system-configs.module';
import { OrdersModule } from '../orders/orders.module';

import { Merchant, MerchantSchema } from '../merchants/schemas/merchant.schema';
import { User, UserSchema } from '../users/schemas/user.schema';
import { DriverProfile, DriverProfileSchema } from '../drivers/schemas/driver-profile.schema';
import { Order, OrderSchema } from '../orders/schemas/order.schema';
import { Table, TableSchema, TableSession, TableSessionSchema } from '../dinein/schemas';

import { AdminApprovalController } from './controllers/admin-merchants.controller';
import { AdminDriversController } from './controllers/admin-drivers.controller';
import { AdminUsersController } from './controllers/admin-users.controller';
import { AdminSystemConfigsController } from './controllers/admin-system-configs.controller';
import { AdminOpsController } from './controllers/admin-ops.controller';

import { AdminApprovalService } from './services/admin-approval.service';
import { AdminUsersService } from './services/admin-users.service';
import { AdminOpsService } from './services/admin-ops.service';

@Module({
  imports: [
    MongooseModule.forFeature([
      { name: User.name, schema: UserSchema },
      { name: Merchant.name, schema: MerchantSchema },
      { name: DriverProfile.name, schema: DriverProfileSchema },
      { name: Order.name, schema: OrderSchema },
      { name: TableSession.name, schema: TableSessionSchema },
      { name: Table.name, schema: TableSchema },
    ]),
    MerchantsModule,
    DriversModule,
    UsersModule,
    OrdersModule,
    SystemConfigsModule,
  ],
  controllers: [
    AdminApprovalController,
    AdminDriversController,
    AdminUsersController,
    AdminSystemConfigsController,
    AdminOpsController,
  ],
  providers: [AdminApprovalService, AdminUsersService, AdminOpsService],
})
export class AdminModule { }
