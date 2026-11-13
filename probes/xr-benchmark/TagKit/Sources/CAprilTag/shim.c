#include "include/CAprilTag.h"

int vbt_detection_count(const zarray_t *detections) {
    return zarray_size(detections);
}

apriltag_detection_t *vbt_detection_at(const zarray_t *detections, int i) {
    apriltag_detection_t *det;
    zarray_get(detections, i, &det);
    return det;
}

double vbt_tag_translation(apriltag_detection_t *det, double tagsize,
                           double fx, double fy, double cx, double cy,
                           double out_t[3]) {
    apriltag_detection_info_t info = {
        .det = det, .tagsize = tagsize, .fx = fx, .fy = fy, .cx = cx, .cy = cy};
    apriltag_pose_t pose;
    double err = estimate_tag_pose(&info, &pose);
    for (int i = 0; i < 3; i++) out_t[i] = MATD_EL(pose.t, i, 0);
    matd_destroy(pose.R);
    matd_destroy(pose.t);
    return err;
}
