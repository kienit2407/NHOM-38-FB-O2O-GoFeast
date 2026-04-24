import { Module, forwardRef } from '@nestjs/common';
import { RealtimeGateway } from './realtime.gateway';
import { DispatchOfferService } from './services/dispatch-offer.service';
import { DineInModule } from '../dinein/dine-in.module';

@Module({
    imports: [forwardRef(() => DineInModule)],
    providers: [RealtimeGateway, DispatchOfferService],
    exports: [DispatchOfferService, RealtimeGateway],
})
export class RealtimeModule { }
