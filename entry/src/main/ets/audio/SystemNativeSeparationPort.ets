import nativeSeparation from 'libpivomic_separation.so';
import { SeparationService } from '../services/SeparationService';
let service: SeparationService | undefined;
export function getSystemSeparationService(): SeparationService {
  if (!service) service = new SeparationService(nativeSeparation);
  return service;
}
