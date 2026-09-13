export interface SeparationSnapshot { phase: string; progress: number; errorMessage: string; sampleRate: number; frameCount: number; }
export const startJob: (inputFd: number, offset: number, size: number, modelPath: string, outputTempPath: string) => number;
export const getJobSnapshot: (jobId: number) => SeparationSnapshot;
export const cancelJob: (jobId: number) => void;
export const releaseJob: (jobId: number) => void;
