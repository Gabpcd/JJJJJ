import { describe, expect, it } from 'vitest';
import capacitorConfig from '../../capacitor.config';

describe('coquille mobile native', () => {
  it('ne cumule pas les insets iOS et ne configure qu’un resize clavier', () => {
    expect(capacitorConfig.ios?.contentInset).toBe('never');
    expect(capacitorConfig.plugins?.Keyboard).toEqual({ resize: 'native' });
  });
});
