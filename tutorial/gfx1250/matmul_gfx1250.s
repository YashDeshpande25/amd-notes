
gfx1250/matmul_gfx1250.hsaco:	file format elf64-amdgpu

Disassembly of section .text:

0000000000001900 <_Z13matmul_kernelPfS_S_j>:
	s_clause 0x1                                               // 000000001900: BF850001
	s_load_b32 s2, s[0:1], 0x2c                                // 000000001904: F4000080 F800002C
	s_load_b32 s8, s[0:1], 0x18                                // 00000000190C: F4000200 F8000018
	s_bfe_u32 s4, ttmp6, 0x4000c                               // 000000001914: 9304FF72 0004000C
	s_bfe_u32 s5, ttmp6, 0x40010                               // 00000000191C: 9305FF72 00040010
	s_add_co_i32 s4, s4, 1                                     // 000000001924: 81048104
	s_add_co_i32 s5, s5, 1                                     // 000000001928: 81058105
	s_and_b32 s3, ttmp6, 15                                    // 00000000192C: 8B038F72
	s_bfe_u32 s6, ttmp6, 0x40004                               // 000000001930: 9306FF72 00040004
	s_mul_i32 s4, ttmp9, s4                                    // 000000001938: 96040475
	s_mul_i32 s5, ttmp7, s5                                    // 00000000193C: 96050573
	s_getreg_b32 s7, hwreg(HW_REG_IB_STS2, 6, 4)               // 000000001940: B887199C
	v_bfe_u32 v1, v0, 10, 10                                   // 000000001944: D6100001 02291500
	v_and_b32_e32 v0, 0x3ff, v0                                // 00000000194C: 360000FF 000003FF
	s_add_co_i32 s3, s3, s4                                    // 000000001954: 81030403
	s_add_co_i32 s6, s6, s5                                    // 000000001958: 81060506
	s_mov_b32 s9, 0                                            // 00000000195C: BE890080
	s_wait_kmcnt 0x0                                           // 000000001960: BFC70000
	s_lshr_b32 s4, s2, 16                                      // 000000001964: 85049002
	s_and_b32 s2, s2, 0xffff                                   // 000000001968: 8B02FF02 0000FFFF
	s_cmp_eq_u32 s7, 0                                         // 000000001970: BF068007
	s_cselect_b32 s5, ttmp7, s6                                // 000000001974: 98050673
	s_cselect_b32 s3, ttmp9, s3                                // 000000001978: 98030375
	v_mad_u32 v1, s5, s4, v1                                   // 00000000197C: D6350001 04040805
	v_mad_u32 v0, s3, s2, v0                                   // 000000001984: D6350000 04000403
	s_mov_b32 s2, exec_lo                                      // 00000000198C: BE82007E
	s_delay_alu instid0(VALU_DEP_1) | instskip(NEXT) | instid1(VALU_DEP_1)// 000000001990: BF870091
	v_max_u32_e32 v2, v1, v0                                   // 000000001994: 28040101
	v_cmpx_gt_u32_e64 s8, v2                                   // 000000001998: D4CC007E 00020408
	s_cbranch_execz 29                                         // 0000000019A0: BFA5001D <_Z13matmul_kernelPfS_S_j+0x118>
	s_clause 0x1                                               // 0000000019A4: BF850001
	s_load_b128 s[4:7], s[0:1], 0x0                            // 0000000019A8: F4004100 F8000000
	s_load_b64 s[2:3], s[0:1], 0x10                            // 0000000019B0: F4002080 F8000010
	v_mul_lo_u32 v1, v1, s8                                    // 0000000019B8: D72C0001 00001101
	v_dual_mov_b32 v2, 0 :: v_dual_mov_b32 v3, v0              // 0000000019C0: CA100080 02020100
	s_delay_alu instid0(VALU_DEP_2)                            // 0000000019C8: BF870002
	v_add_nc_u32_e32 v4, s9, v1                                // 0000000019CC: 4A080209
	s_add_co_i32 s9, s9, 1                                     // 0000000019D0: 81098109
	s_wait_kmcnt 0x0                                           // 0000000019D4: BFC70000
	global_load_b32 v5, v3, s[6:7] scale_offset                // 0000000019D8: EE050006 00010005 00000003
	global_load_b32 v6, v4, s[4:5] scale_offset                // 0000000019E4: EE050004 00010006 00000004
	s_wait_xcnt 0x1                                            // 0000000019F0: BFC50001
	v_add_nc_u32_e32 v3, s8, v3                                // 0000000019F4: 4A060608
	s_cmp_eq_u32 s8, s9                                        // 0000000019F8: BF060908
	s_wait_loadcnt 0x0                                         // 0000000019FC: BFC00000
	v_fmac_f32_e32 v2, v6, v5                                  // 000000001A00: 56040B06
	s_cbranch_scc0 65520                                       // 000000001A04: BFA1FFF0 <_Z13matmul_kernelPfS_S_j+0xc8>
	v_add_nc_u32_e32 v0, v1, v0                                // 000000001A08: 4A000101
	global_store_b32 v0, v2, s[2:3] scale_offset               // 000000001A0C: EE068002 01010000 00000000
	s_endpgm                                                   // 000000001A18: BFB00000
	s_code_end                                                 // 000000001A1C: BF9F0000
	s_code_end                                                 // 000000001A20: BF9F0000
	s_code_end                                                 // 000000001A24: BF9F0000
	s_code_end                                                 // 000000001A28: BF9F0000
	s_code_end                                                 // 000000001A2C: BF9F0000
	s_code_end                                                 // 000000001A30: BF9F0000
	s_code_end                                                 // 000000001A34: BF9F0000
	s_code_end                                                 // 000000001A38: BF9F0000
	s_code_end                                                 // 000000001A3C: BF9F0000
	s_code_end                                                 // 000000001A40: BF9F0000
	s_code_end                                                 // 000000001A44: BF9F0000
	s_code_end                                                 // 000000001A48: BF9F0000
	s_code_end                                                 // 000000001A4C: BF9F0000
	s_code_end                                                 // 000000001A50: BF9F0000
	s_code_end                                                 // 000000001A54: BF9F0000
	s_code_end                                                 // 000000001A58: BF9F0000
	s_code_end                                                 // 000000001A5C: BF9F0000
	s_code_end                                                 // 000000001A60: BF9F0000
	s_code_end                                                 // 000000001A64: BF9F0000
	s_code_end                                                 // 000000001A68: BF9F0000
	s_code_end                                                 // 000000001A6C: BF9F0000
	s_code_end                                                 // 000000001A70: BF9F0000
	s_code_end                                                 // 000000001A74: BF9F0000
	s_code_end                                                 // 000000001A78: BF9F0000
	s_code_end                                                 // 000000001A7C: BF9F0000
	s_code_end                                                 // 000000001A80: BF9F0000
	s_code_end                                                 // 000000001A84: BF9F0000
	s_code_end                                                 // 000000001A88: BF9F0000
	s_code_end                                                 // 000000001A8C: BF9F0000
	s_code_end                                                 // 000000001A90: BF9F0000
	s_code_end                                                 // 000000001A94: BF9F0000
	s_code_end                                                 // 000000001A98: BF9F0000
	s_code_end                                                 // 000000001A9C: BF9F0000
	s_code_end                                                 // 000000001AA0: BF9F0000
	s_code_end                                                 // 000000001AA4: BF9F0000
	s_code_end                                                 // 000000001AA8: BF9F0000
	s_code_end                                                 // 000000001AAC: BF9F0000
	s_code_end                                                 // 000000001AB0: BF9F0000
	s_code_end                                                 // 000000001AB4: BF9F0000
	s_code_end                                                 // 000000001AB8: BF9F0000
	s_code_end                                                 // 000000001ABC: BF9F0000
	s_code_end                                                 // 000000001AC0: BF9F0000
	s_code_end                                                 // 000000001AC4: BF9F0000
	s_code_end                                                 // 000000001AC8: BF9F0000
	s_code_end                                                 // 000000001ACC: BF9F0000
	s_code_end                                                 // 000000001AD0: BF9F0000
	s_code_end                                                 // 000000001AD4: BF9F0000
	s_code_end                                                 // 000000001AD8: BF9F0000
	s_code_end                                                 // 000000001ADC: BF9F0000
	s_code_end                                                 // 000000001AE0: BF9F0000
	s_code_end                                                 // 000000001AE4: BF9F0000
	s_code_end                                                 // 000000001AE8: BF9F0000
	s_code_end                                                 // 000000001AEC: BF9F0000
	s_code_end                                                 // 000000001AF0: BF9F0000
	s_code_end                                                 // 000000001AF4: BF9F0000
	s_code_end                                                 // 000000001AF8: BF9F0000
	s_code_end                                                 // 000000001AFC: BF9F0000
	s_code_end                                                 // 000000001B00: BF9F0000
	s_code_end                                                 // 000000001B04: BF9F0000
	s_code_end                                                 // 000000001B08: BF9F0000
	s_code_end                                                 // 000000001B0C: BF9F0000
	s_code_end                                                 // 000000001B10: BF9F0000
	s_code_end                                                 // 000000001B14: BF9F0000
	s_code_end                                                 // 000000001B18: BF9F0000
	s_code_end                                                 // 000000001B1C: BF9F0000
	s_code_end                                                 // 000000001B20: BF9F0000
	s_code_end                                                 // 000000001B24: BF9F0000
	s_code_end                                                 // 000000001B28: BF9F0000
	s_code_end                                                 // 000000001B2C: BF9F0000
	s_code_end                                                 // 000000001B30: BF9F0000
	s_code_end                                                 // 000000001B34: BF9F0000
	s_code_end                                                 // 000000001B38: BF9F0000
	s_code_end                                                 // 000000001B3C: BF9F0000
	s_code_end                                                 // 000000001B40: BF9F0000
	s_code_end                                                 // 000000001B44: BF9F0000
	s_code_end                                                 // 000000001B48: BF9F0000
	s_code_end                                                 // 000000001B4C: BF9F0000
	s_code_end                                                 // 000000001B50: BF9F0000
	s_code_end                                                 // 000000001B54: BF9F0000
	s_code_end                                                 // 000000001B58: BF9F0000
	s_code_end                                                 // 000000001B5C: BF9F0000
	s_code_end                                                 // 000000001B60: BF9F0000
	s_code_end                                                 // 000000001B64: BF9F0000
	s_code_end                                                 // 000000001B68: BF9F0000
	s_code_end                                                 // 000000001B6C: BF9F0000
	s_code_end                                                 // 000000001B70: BF9F0000
	s_code_end                                                 // 000000001B74: BF9F0000
	s_code_end                                                 // 000000001B78: BF9F0000
	s_code_end                                                 // 000000001B7C: BF9F0000
	s_code_end                                                 // 000000001B80: BF9F0000
	s_code_end                                                 // 000000001B84: BF9F0000
	s_code_end                                                 // 000000001B88: BF9F0000
	s_code_end                                                 // 000000001B8C: BF9F0000
	s_code_end                                                 // 000000001B90: BF9F0000
	s_code_end                                                 // 000000001B94: BF9F0000
	s_code_end                                                 // 000000001B98: BF9F0000
	s_code_end                                                 // 000000001B9C: BF9F0000
	s_code_end                                                 // 000000001BA0: BF9F0000
	s_code_end                                                 // 000000001BA4: BF9F0000
	s_code_end                                                 // 000000001BA8: BF9F0000
	s_code_end                                                 // 000000001BAC: BF9F0000
	s_code_end                                                 // 000000001BB0: BF9F0000
	s_code_end                                                 // 000000001BB4: BF9F0000
	s_code_end                                                 // 000000001BB8: BF9F0000
	s_code_end                                                 // 000000001BBC: BF9F0000
	s_code_end                                                 // 000000001BC0: BF9F0000
	s_code_end                                                 // 000000001BC4: BF9F0000
	s_code_end                                                 // 000000001BC8: BF9F0000
	s_code_end                                                 // 000000001BCC: BF9F0000
	s_code_end                                                 // 000000001BD0: BF9F0000
	s_code_end                                                 // 000000001BD4: BF9F0000
	s_code_end                                                 // 000000001BD8: BF9F0000
	s_code_end                                                 // 000000001BDC: BF9F0000
	s_code_end                                                 // 000000001BE0: BF9F0000
	s_code_end                                                 // 000000001BE4: BF9F0000
	s_code_end                                                 // 000000001BE8: BF9F0000
	s_code_end                                                 // 000000001BEC: BF9F0000
	s_code_end                                                 // 000000001BF0: BF9F0000
	s_code_end                                                 // 000000001BF4: BF9F0000
	s_code_end                                                 // 000000001BF8: BF9F0000
	s_code_end                                                 // 000000001BFC: BF9F0000
