import { Module, forwardRef } from '@nestjs/common';
import { MongooseModule } from '@nestjs/mongoose';
import { JwtModule } from '@nestjs/jwt';

import { MerchantTablesController } from './controllers/merchant-tables.controller';
import { PublicDineInController } from './controllers/public-dine-in.controller';

import { Table, TableSchema } from './schemas/table.schema';
import { TableSession, TableSessionSchema } from './schemas/table-session.schema';

import { TablesService } from './services/tables.service';
import { DineInSessionTokenService } from './services/dinein-session-token.service';
import { DineInSessionGuard } from './guards/dinein-session.guard';
import { PublicDineInService } from './services/public-dinein.service';

import { Merchant, MerchantSchema } from '../merchants/schemas';
import { RealtimeModule } from '../realtime/realtime.module';

@Module({
    imports: [
        JwtModule.register({}),
        MongooseModule.forFeature([
            { name: Table.name, schema: TableSchema },
            { name: TableSession.name, schema: TableSessionSchema },
            { name: Merchant.name, schema: MerchantSchema },
        ]),
        forwardRef(() => RealtimeModule),
    ],
    controllers: [
        MerchantTablesController,
        PublicDineInController,
    ],
    providers: [
        TablesService,
        PublicDineInService,
        DineInSessionTokenService,
        DineInSessionGuard,
    ],
    exports: [
        TablesService,
        PublicDineInService,
        DineInSessionTokenService,
        DineInSessionGuard,
        MongooseModule,
    ],
})
export class DineInModule { }
