#ifndef CSystemShims_h
#define CSystemShims_h

#include <libproc.h>
#include <sys/proc_info.h>
#include <sys/sysctl.h>
#include <sys/resource.h>
#include <stdint.h>

// SMC access is undocumented: no public Apple header declares AppleSMC's
// user-client struct layout. This mirrors the layout used by long-standing
// open-source tools (smcFanControl, iStats, smckit) so IOConnectCallStructMethod
// receives byte-identical structs to what AppleSMC.kext expects.

typedef struct {
    unsigned char major;
    unsigned char minor;
    unsigned char build;
    unsigned char reserved;
    unsigned short release;
} SMCKeyData_vers_t;

typedef struct {
    unsigned short version;
    unsigned short length;
    uint32_t cpuPLimit;
    uint32_t gpuPLimit;
    uint32_t memPLimit;
} SMCKeyData_pLimitData_t;

typedef struct {
    uint32_t dataSize;
    uint32_t dataType;
    unsigned char dataAttributes;
} SMCKeyData_keyInfo_t;

typedef struct {
    uint32_t key;
    SMCKeyData_vers_t vers;
    SMCKeyData_pLimitData_t pLimitData;
    SMCKeyData_keyInfo_t keyInfo;
    unsigned char result;
    unsigned char status;
    unsigned char data8;
    uint32_t data32;
    unsigned char bytes[32];
} SMCParamStruct;

enum {
    kSMCUserClientOpen  = 0,
    kSMCUserClientClose = 1,
    kSMCHandleYPCEvent  = 2,
    kSMCReadKey         = 5,
    kSMCWriteKey        = 6,
    kSMCGetKeyCount     = 7,
    kSMCGetKeyFromIndex = 8,
    kSMCGetKeyInfo      = 9
};

#endif /* CSystemShims_h */
