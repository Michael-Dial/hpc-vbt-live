#ifndef CAPRILTAG_H
#define CAPRILTAG_H

#include "../apriltag/apriltag.h"
#include "../apriltag/apriltag_pose.h"
#include "../apriltag/tag36h11.h"
#include "../apriltag/tagStandard41h12.h"

/// Number of detections in the array returned by apriltag_detector_detect.
int vbt_detection_count(const zarray_t *detections);

/// The i-th detection. Owned by the array.
apriltag_detection_t *vbt_detection_at(const zarray_t *detections, int i);

/// Tag position in the camera frame, in metres. Returns the object-space error.
/// Swift cannot read matd_t (flexible array member), so this copies t out.
double vbt_tag_translation(apriltag_detection_t *det, double tagsize,
                           double fx, double fy, double cx, double cy,
                           double out_t[3]);

#endif
