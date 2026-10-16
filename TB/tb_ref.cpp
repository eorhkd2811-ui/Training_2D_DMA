// Descriptor-driven DMA reference model for the SystemVerilog DPI scoreboard.
// Scope: two channels, equal 256-bit source/destination beats, BYTE addresses,
// finite transfers and row strides. INCR and basic FIX address mapping supported.
// Not a cycle model: no arbitration/order prediction across different channels.
// No byte strobes, width conversion, cyclic transfers or out-of-order completion.
// The model snapshots expected DATA from seeded source memory when a descriptor
// is registered. Actual DUT read addresses never participate in prediction.
// Mutating API convention: 1 = success, 0 = failure; failures accumulate errors.

#include "svdpi.h"
#include <array>
#include <algorithm>
#include <cstdint>
#include <cstdio>
#include <deque>
#include <limits>
#include <map>
#include <vector>

namespace {
void reset_predictor();
const int kChannels = 2;
const unsigned kLimbs = 8; // DPI bit[255:0]: least-significant limb first.
const unsigned kBeatBytes = 32;
const unsigned kDetailLimit = 32;
const std::uint64_t kMaxQueuedBeats = 4u * 1024u * 1024u;
typedef std::array<std::uint32_t, kLimbs> Word;
struct ExpectedBeat {
    std::uint32_t address;
    Word data;
};

std::map<std::uint32_t, Word> source_words;
std::deque<ExpectedBeat> expected[kChannels];
int checked[kChannels] = {0, 0};
int errors = 0;
unsigned printed_errors = 0;

bool valid_channel(int channel) {
    return channel >= 0 && channel < kChannels;
}

bool detail_allowed() {
    ++errors;
    if (printed_errors < kDetailLimit) {
        ++printed_errors;
        return true;
    }
    if (printed_errors == kDetailLimit) {
        ++printed_errors;
        std::printf("[REF] Further detailed error messages suppressed.\n");
    }
    return false;
}

int fail(const char* message) {
    if (detail_allowed()) std::printf("[REF ERROR] %s\n", message);
    std::fflush(stdout);
    return 0;
}

Word unpack(const svBitVecVal* data) {
    Word word;
    for (unsigned i = 0; i < kLimbs; ++i) word[i] = data[i];
    return word;
}

void print_word(const Word& word) {
    for (int i = static_cast<int>(kLimbs) - 1; i >= 0; --i)
        std::printf("%08x", static_cast<unsigned>(word[i]));
}

std::uint64_t address_of(unsigned int base, int row, int col,
                         int stride, int increment) {
    return static_cast<std::uint64_t>(base) +
        (increment ? static_cast<std::uint64_t>(row) * stride +
                     static_cast<std::uint64_t>(col) * kBeatBytes : 0);
}
} // namespace

extern "C" int dma_ref_reset() {
    reset_predictor();
    source_words.clear();
    for (int channel = 0; channel < kChannels; ++channel) {
        expected[channel].clear();
        checked[channel] = 0;
    }
    errors = 0;
    printed_errors = 0;
    return 1;
}

extern "C" int dma_ref_seed(unsigned int byte_addr, const svBitVecVal* data) {
    if (!data) return fail("dma_ref_seed received null data");
    if (byte_addr % kBeatBytes) return fail("unaligned source seed byte address");
    source_words[byte_addr] = unpack(data);
    return 1;
}

extern "C" int dma_ref_expect(int channel, unsigned int src, unsigned int dst,
                               int x_words, int y_rows, int src_stride,
                               int dst_stride, int src_incr, int dst_incr) {
    if (!valid_channel(channel)) return fail("invalid descriptor channel");
    if (x_words <= 0 || y_rows <= 0 || src_stride < 0 || dst_stride < 0)
        return fail("descriptor needs positive counts and nonnegative strides");
    if (x_words > 65536 || y_rows > 65536 || src_stride > 65535 || dst_stride > 65535)
        return fail("descriptor exceeds 16-bit length/stride fields");
    if (src % kBeatBytes || dst % kBeatBytes ||
        src_stride % kBeatBytes || dst_stride % kBeatBytes)
        return fail("memory addresses and strides require 32-byte alignment");
    if ((src_incr != 0 && src_incr != 1) || (dst_incr != 0 && dst_incr != 1))
        return fail("descriptor increment flags must be 0 or 1");
    const std::uint64_t count = static_cast<std::uint64_t>(x_words) * y_rows;
    if (count + expected[channel].size() > kMaxQueuedBeats)
        return fail("descriptor exceeds reference queue safety limit");
    const std::uint64_t max_addr = std::numeric_limits<std::uint32_t>::max();
    if (address_of(src, y_rows - 1, x_words - 1, src_stride, src_incr) > max_addr-(kBeatBytes-1) ||
        address_of(dst, y_rows - 1, x_words - 1, dst_stride, dst_incr) > max_addr-(kBeatBytes-1))
        return fail("descriptor byte access overflows 32-bit address space");

    // Build a temporary snapshot first: invalid descriptors enqueue no partial
    // expectations and therefore cannot silently change the scoreboard contract.
    std::vector<ExpectedBeat> snapshot;
    snapshot.reserve(static_cast<std::size_t>(count));
    for (int row = 0; row < y_rows; ++row) {
        for (int col = 0; col < x_words; ++col) {
            const std::uint32_t source = static_cast<std::uint32_t>(
                address_of(src, row, col, src_stride, src_incr));
            const auto found = source_words.find(source);
            if (found == source_words.end()) {
                if (detail_allowed())
                    std::printf("[REF ERROR] Unseeded source byte address 0x%08x "
                                "for channel=%d row=%d column=%d\n",
                                static_cast<unsigned>(source), channel, row, col);
                std::fflush(stdout);
                return 0;
            }
            ExpectedBeat beat;
            beat.address = static_cast<std::uint32_t>(
                address_of(dst, row, col, dst_stride, dst_incr));
            beat.data = found->second;
            snapshot.push_back(beat);
        }
    }
    expected[channel].insert(expected[channel].end(), snapshot.begin(), snapshot.end());
    std::printf("[REF] Expect channel=%d beats=%llu src=0x%08x dst=0x%08x "
                "rows=%d words/row=%d\n", channel,
                static_cast<unsigned long long>(count), src, dst, y_rows, x_words);
    std::fflush(stdout);
    return 1;
}

extern "C" int dma_ref_check(int channel, unsigned int dst,
                              const svBitVecVal* actual) {
    if (!valid_channel(channel)) return fail("invalid observed channel");
    ++checked[channel];
    if (expected[channel].empty()) {
        if (detail_allowed())
            std::printf("[REF ERROR] Unexpected beat channel=%d observed=%d "
                        "dst=0x%08x\n", channel, checked[channel], dst);
        std::fflush(stdout);
        return 0;
    }
    // Always consume one expectation per observed beat, including bad beats,
    // so one corrupt value does not cause spurious failures of all later data.
    const ExpectedBeat wanted = expected[channel].front();
    expected[channel].pop_front();
    if (!actual) return fail("dma_ref_check received null data");
    const Word observed = unpack(actual);
    const bool address_ok = dst == wanted.address;
    const bool data_ok = observed == wanted.data;
    if (address_ok && data_ok) return 1;
    if (detail_allowed()) {
        std::printf("[REF ERROR] Beat mismatch channel=%d observed=%d "
                    "actual_dst=0x%08x expected_dst=0x%08x address_ok=%d data_ok=%d\n",
                    channel, checked[channel], dst,
                    static_cast<unsigned>(wanted.address), address_ok, data_ok);
        std::printf("  actual:   0x"); print_word(observed);
        std::printf("\n  expected: 0x"); print_word(wanted.data);
        std::printf("\n");
    }
    std::fflush(stdout);
    return 0;
}

extern "C" int dma_ref_remaining(int channel) {
    if (!valid_channel(channel)) { fail("invalid remaining-count channel"); return -1; }
    return static_cast<int>(expected[channel].size());
}

extern "C" int dma_ref_checked(int channel) {
    if (!valid_channel(channel)) { fail("invalid checked-count channel"); return -1; }
    return checked[channel];
}

extern "C" int dma_ref_errors() { return errors; }

extern "C" void dma_ref_report() {
    std::printf("[REF SUMMARY] errors=%d", errors);
    for (int channel = 0; channel < kChannels; ++channel)
        std::printf(" channel%d_checked=%d channel%d_remaining=%llu", channel,
                    checked[channel], channel,
                    static_cast<unsigned long long>(expected[channel].size()));
    std::printf("\n");
    std::fflush(stdout);
}

// Settings-based burst predictor. Independent from source-data snapshots above.
// Exact burst sizes encode this DMA's maximal-legal-burst POLICY, not an AXI
// protocol rule. Protocol legality is checked separately in tb_drv.
namespace {
struct Burst {
    std::uint32_t address;
    unsigned beats, descriptor, row, ordinal;
    int reason; // -1=no shortening; 0=source; 1=destination; 2=both tied.
};
struct PredChannel {
    bool configured=false;
    int id=-1;
    unsigned max_beats=0, next_descriptor=0;
    std::deque<Burst> request[2]; // 0 AR, 1 AW; cross-channel order is unconstrained.
    std::uint64_t expected_requests=0, expected_beats=0;
    std::uint64_t observed_requests[2]={0,0}, observed_beats[2]={0,0};
    std::uint64_t shortened[3]={0,0,0}, matched_shortened[2][3]={{0,0,0},{0,0,0}};
};
PredChannel pred[kChannels];
void reset_predictor() { for(auto& c:pred) c=PredChannel{}; }
}

extern "C" int dma_pred_channel(int id) {
    for(int ch=0;ch<kChannels;++ch)
        if(pred[ch].configured && pred[ch].id==id) return ch;
    return -1;
}
extern "C" int dma_pred_config(int channel,int id,int max_beats,
                                  int src_burst,int dst_burst,int beat_bytes) {
    if(!valid_channel(channel) || id<0 || id>=32 || max_beats<1 || max_beats>256)
        return fail("[PRED] invalid channel/ID/max_beats");
    if(src_burst!=1 || dst_burst!=1 || beat_bytes!=32)
        return fail("[PRED] scope is aligned INCR/INCR, equal 32-byte beats");
    if(pred[channel].configured) return fail("[PRED] active channel reconfiguration unsupported");
    if(dma_pred_channel(id)>=0) return fail("[PRED] active channels require distinct AXI IDs");
    pred[channel].configured=true; pred[channel].id=id; pred[channel].max_beats=max_beats;
    return 1;
}
extern "C" int dma_pred_expect(int channel,unsigned int src,unsigned int dst,
    int x_words,int y_rows,int src_stride,int dst_stride) {
    if(!valid_channel(channel) || !pred[channel].configured)
        return fail("[PRED] descriptor needs configured channel");
    if(x_words<1 || x_words>65536 || y_rows<1 || y_rows>65536 ||
       src_stride<0 || src_stride>65535 || dst_stride<0 || dst_stride>65535 ||
       src%kBeatBytes || dst%kBeatBytes || src_stride%kBeatBytes || dst_stride%kBeatBytes)
        return fail("[PRED] invalid descriptor encoding/alignment");
    const std::uint64_t count=std::uint64_t(x_words)*y_rows;
    auto& c=pred[channel];
    if(count+c.request[0].size()>kMaxQueuedBeats ||
       count+c.request[1].size()>kMaxQueuedBeats)
        return fail("[PRED] queue safety limit exceeded");
    if(address_of(src,y_rows-1,x_words-1,src_stride,1)>UINT32_MAX-(kBeatBytes-1) ||
       address_of(dst,y_rows-1,x_words-1,dst_stride,1)>UINT32_MAX-(kBeatBytes-1))
        return fail("[PRED] 32-bit address overflow");
    std::vector<Burst> temp[2];
    std::uint64_t short_count[3]={0,0,0};
    for(int row=0;row<y_rows;++row) {
        std::uint64_t s=std::uint64_t(src)+std::uint64_t(row)*src_stride;
        std::uint64_t d=std::uint64_t(dst)+std::uint64_t(row)*dst_stride;
        unsigned remaining=x_words,ordinal=0;
        while(remaining) {
            const unsigned base=std::min(remaining,std::min(c.max_beats,256u));
            const unsigned sl=(4096u-unsigned(s%4096))/kBeatBytes;
            const unsigned dl=(4096u-unsigned(d%4096))/kBeatBytes;
            const unsigned n=std::min(base,std::min(sl,dl));
            if(!n) return fail("[PRED] zero-sized burst");
            int reason=-1;
            if(n<base) {
                reason=(sl==dl)?2:(sl<dl?0:1);
                ++short_count[reason];
            }
            Burst ar{std::uint32_t(s),n,c.next_descriptor,unsigned(row),ordinal,reason};
            Burst aw=ar; aw.address=std::uint32_t(d);
            temp[0].push_back(ar); temp[1].push_back(aw);
            s+=std::uint64_t(n)*kBeatBytes; d+=std::uint64_t(n)*kBeatBytes;
            remaining-=n; ++ordinal;
        }
    }
    // No partial enqueue on invalid configuration.
    for(int path=0;path<2;++path)
        c.request[path].insert(c.request[path].end(),temp[path].begin(),temp[path].end());
    c.expected_requests+=temp[0].size(); c.expected_beats+=count;
    for(int r=0;r<3;++r) c.shortened[r]+=short_count[r];
    std::printf("[PRED EXPECT] ch=%d desc=%u bursts=%zu beats=%llu shortened_src/dst/both=%llu/%llu/%llu\n",
        channel,c.next_descriptor,temp[0].size(),(unsigned long long)count,
        (unsigned long long)short_count[0],(unsigned long long)short_count[1],(unsigned long long)short_count[2]);
    ++c.next_descriptor; std::fflush(stdout); return 1;
}
extern "C" int dma_pred_check(int is_write,int id,unsigned int address,int len,int size,int burst) {
    const int ch=dma_pred_channel(id);
    if(ch<0 || (is_write!=0 && is_write!=1)) return fail("[PRED] unknown AXI ID/path");
    auto& c=pred[ch]; auto& q=c.request[is_write];
    if(q.empty()) return fail("[PRED] unexpected extra AR/AW request");
    const Burst b=q.front();
    if(address!=b.address || len!=int(b.beats)-1 || size!=5 || burst!=1) {
        if(detail_allowed()) std::printf(
            "[PRED ERROR] %s ch=%d ID=%d desc=%u row=%u burst=%u actual_addr/len/size/type=%08x/%d/%d/%d expected=%08x/%u/5/1\n",
            is_write?"AW":"AR",ch,id,b.descriptor,b.row,b.ordinal,address,len,size,burst,b.address,b.beats-1);
        std::fflush(stdout); return 0;
    }
    q.pop_front(); ++c.observed_requests[is_write]; c.observed_beats[is_write]+=b.beats;
    // Count boundary coverage only after all request fields matched.
    if(b.reason>=0) ++c.matched_shortened[is_write][b.reason];
    return 1;
}
extern "C" int dma_pred_pending(int channel,int is_write) {
    if(!valid_channel(channel) || (is_write!=0 && is_write!=1)) {
        fail("[PRED] invalid pending query"); return -1;
    }
    return int(pred[channel].request[is_write].size());
}
extern "C" void dma_pred_report() {
    for(int ch=0;ch<kChannels;++ch) {
        const auto& c=pred[ch];
        std::printf("[PRED SUMMARY] ch=%d id=%d descriptors=%u expected_bursts=%llu expected_beats=%llu AR/AW=%llu/%llu ARbeats/AWbeats=%llu/%llu pending_AR/AW=%zu/%zu\n",
            ch,c.id,c.next_descriptor,(unsigned long long)c.expected_requests,(unsigned long long)c.expected_beats,
            (unsigned long long)c.observed_requests[0],(unsigned long long)c.observed_requests[1],
            (unsigned long long)c.observed_beats[0],(unsigned long long)c.observed_beats[1],c.request[0].size(),c.request[1].size());
        const char* names[3]={"source_limited","destination_limited","tied_limited"};
        for(int r=0;r<3;++r) std::printf("[PRED COVERAGE] ch=%d %s expected=%llu matched_AR=%llu matched_AW=%llu\n",ch,names[r],
            (unsigned long long)c.shortened[r],(unsigned long long)c.matched_shortened[0][r],(unsigned long long)c.matched_shortened[1][r]);
    }
    std::fflush(stdout);
}
extern "C" int dma_pred_finish() {
    for(const auto& c:pred) for(int path=0;path<2;++path) {
        if(!c.configured || !c.request[path].empty() || c.observed_requests[path]!=c.expected_requests ||
           c.observed_beats[path]!=c.expected_beats) return fail("[PRED] undrained/count mismatch");
        for(int r=0;r<3;++r) if(c.matched_shortened[path][r]!=c.shortened[r])
            return fail("[PRED] expected boundary event not observed");
    }
    return 1;
}
